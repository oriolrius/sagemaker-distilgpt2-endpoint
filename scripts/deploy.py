#!/usr/bin/env python3
"""
Deploy DistilGPT-2 model to SageMaker endpoint.
Downloads model from Hugging Face, packages with inference code, and deploys.
"""

import os
import tarfile
import tempfile
import shutil
import boto3
import sagemaker
from datetime import datetime
from transformers import AutoTokenizer, AutoModelForCausalLM

# Configuration
REGION = os.environ.get("AWS_REGION", "eu-north-1")
MODEL_NAME = "distilgpt2"
INSTANCE_TYPE = "ml.m5.large"

# PyTorch inference container
CONTAINER_IMAGE = "763104351884.dkr.ecr.eu-north-1.amazonaws.com/pytorch-inference:2.0.1-cpu-py310"


def get_role_arn():
    """Get SageMaker execution role ARN"""
    iam = boto3.client('iam', region_name=REGION)

    # Try common SageMaker role names
    role_names = [
        "AmazonSageMakerAdminIAMExecutionRole",
        "SageMakerExecutionRole",
        "AmazonSageMaker-ExecutionRole"
    ]

    for role_name in role_names:
        try:
            response = iam.get_role(RoleName=role_name)
            return response['Role']['Arn']
        except iam.exceptions.NoSuchEntityException:
            continue

    # If no standard role found, try to get from SageMaker session
    try:
        session = sagemaker.Session()
        return sagemaker.get_execution_role(sagemaker_session=session)
    except Exception:
        pass

    raise RuntimeError("Could not find SageMaker execution role. Set SAGEMAKER_ROLE_ARN environment variable.")


def download_model(model_dir):
    """Download model from Hugging Face"""
    print(f"Downloading {MODEL_NAME} from Hugging Face...")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    model = AutoModelForCausalLM.from_pretrained(MODEL_NAME)

    model.save_pretrained(model_dir)
    tokenizer.save_pretrained(model_dir)
    print(f"Model saved to {model_dir}")


def package_model(model_dir, code_dir, output_path):
    """Package model and code into tarball"""
    print(f"Creating model tarball...")

    with tarfile.open(output_path, "w:gz") as tar:
        # Add model files
        for item in os.listdir(model_dir):
            tar.add(os.path.join(model_dir, item), arcname=item)

        # Add code directory
        tar.add(code_dir, arcname="code")

    print(f"Created {output_path}")


def upload_to_s3(local_path, bucket, key):
    """Upload file to S3"""
    print(f"Uploading to s3://{bucket}/{key}...")
    s3 = boto3.client('s3', region_name=REGION)
    s3.upload_file(local_path, bucket, key)
    return f"s3://{bucket}/{key}"


def deploy_endpoint(model_uri, role_arn):
    """Deploy SageMaker endpoint"""
    sm = boto3.client('sagemaker', region_name=REGION)
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")

    model_name = f"distilgpt2-{timestamp}"
    endpoint_config_name = f"distilgpt2-config-{timestamp}"
    endpoint_name = f"distilgpt2-endpoint-{timestamp}"

    # Create model
    print(f"Creating model: {model_name}")
    sm.create_model(
        ModelName=model_name,
        PrimaryContainer={
            'Image': CONTAINER_IMAGE,
            'ModelDataUrl': model_uri,
            'Environment': {
                'SAGEMAKER_PROGRAM': 'inference.py',
                'SAGEMAKER_SUBMIT_DIRECTORY': model_uri,
            }
        },
        ExecutionRoleArn=role_arn
    )

    # Create endpoint config
    print(f"Creating endpoint config: {endpoint_config_name}")
    sm.create_endpoint_config(
        EndpointConfigName=endpoint_config_name,
        ProductionVariants=[{
            'VariantName': 'AllTraffic',
            'ModelName': model_name,
            'InitialInstanceCount': 1,
            'InstanceType': INSTANCE_TYPE,
            'InitialVariantWeight': 1.0
        }]
    )

    # Create endpoint
    print(f"Creating endpoint: {endpoint_name}")
    sm.create_endpoint(
        EndpointName=endpoint_name,
        EndpointConfigName=endpoint_config_name
    )

    return endpoint_name


def main():
    # Get role ARN from environment or auto-detect
    role_arn = os.environ.get("SAGEMAKER_ROLE_ARN") or get_role_arn()
    print(f"Using role: {role_arn}")

    # Get S3 bucket
    session = sagemaker.Session()
    bucket = session.default_bucket()

    # Get code directory (relative to this script)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    code_dir = os.path.join(script_dir, "..", "code")

    if not os.path.exists(code_dir):
        raise RuntimeError(f"Code directory not found: {code_dir}")

    with tempfile.TemporaryDirectory() as tmpdir:
        model_dir = os.path.join(tmpdir, "model")
        os.makedirs(model_dir)

        # Download model
        download_model(model_dir)

        # Package model
        tarball_path = os.path.join(tmpdir, "model.tar.gz")
        package_model(model_dir, code_dir, tarball_path)

        # Upload to S3
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        s3_key = f"distilgpt2-model/model-{timestamp}.tar.gz"
        model_uri = upload_to_s3(tarball_path, bucket, s3_key)

        # Deploy endpoint
        endpoint_name = deploy_endpoint(model_uri, role_arn)

        print(f"\nEndpoint creation started: {endpoint_name}")
        print(f"Wait for endpoint with: aws sagemaker wait endpoint-in-service --endpoint-name {endpoint_name}")


if __name__ == "__main__":
    main()
