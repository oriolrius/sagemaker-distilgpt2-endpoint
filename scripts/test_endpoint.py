#!/usr/bin/env python3
"""
Test a deployed SageMaker endpoint.
"""

import os
import sys
import json
import boto3

REGION = os.environ.get("AWS_REGION", "eu-north-1")


def test_endpoint(endpoint_name):
    """Test the endpoint with a sample prompt"""
    runtime = boto3.client('sagemaker-runtime', region_name=REGION)

    payload = {"inputs": "The future of artificial intelligence"}

    print(f"Testing endpoint: {endpoint_name}")
    print(f"Payload: {payload}")

    response = runtime.invoke_endpoint(
        EndpointName=endpoint_name,
        ContentType='application/json',
        Body=json.dumps(payload)
    )

    result = json.loads(response['Body'].read().decode())
    print(f"Response: {result}")

    # Verify response has expected structure
    if 'generated_text' not in result:
        print("ERROR: Response missing 'generated_text' field")
        return False

    if not result['generated_text'].strip():
        print("ERROR: Generated text is empty")
        return False

    print("SUCCESS: Endpoint is working correctly")
    return True


def get_latest_endpoint():
    """Find the most recent distilgpt2 endpoint"""
    sm = boto3.client('sagemaker', region_name=REGION)

    response = sm.list_endpoints(
        SortBy='CreationTime',
        SortOrder='Descending',
        MaxResults=10
    )

    for endpoint in response['Endpoints']:
        if 'distilgpt2' in endpoint['EndpointName'].lower():
            if endpoint['EndpointStatus'] == 'InService':
                return endpoint['EndpointName']

    return None


def main():
    # Get endpoint name from argument, environment, or auto-detect
    if len(sys.argv) > 1:
        endpoint_name = sys.argv[1]
    else:
        endpoint_name = os.environ.get("SAGEMAKER_ENDPOINT_NAME")

    if not endpoint_name:
        print("No endpoint specified, searching for latest distilgpt2 endpoint...")
        endpoint_name = get_latest_endpoint()

    if not endpoint_name:
        print("ERROR: No endpoint found. Specify endpoint name as argument or SAGEMAKER_ENDPOINT_NAME env var.")
        sys.exit(1)

    success = test_endpoint(endpoint_name)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
