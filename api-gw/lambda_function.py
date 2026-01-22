"""
Lambda function that proxies OpenAI-compatible requests to SageMaker vLLM endpoint.
Handles AWS SigV4 signing automatically via boto3.
"""

import json
import os
import boto3

# Get configuration from environment variables
SAGEMAKER_ENDPOINT_NAME = os.environ.get('SAGEMAKER_ENDPOINT_NAME')
AWS_REGION = os.environ.get('AWS_REGION', 'eu-north-1')

# Initialize SageMaker runtime client
sagemaker_runtime = boto3.client('sagemaker-runtime', region_name=AWS_REGION)


def lambda_handler(event, context):
    """
    Handle incoming API Gateway requests and forward to SageMaker endpoint.

    Supports:
    - POST /v1/chat/completions - OpenAI chat completions format
    - POST /v1/completions - OpenAI completions format
    - GET /v1/models - List available models
    """

    # Parse the request
    http_method = event.get('httpMethod', event.get('requestContext', {}).get('http', {}).get('method', 'POST'))
    path = event.get('path', event.get('rawPath', '/'))

    # Handle GET /v1/models
    if http_method == 'GET' and '/models' in path:
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'object': 'list',
                'data': [
                    {
                        'id': SAGEMAKER_ENDPOINT_NAME,
                        'object': 'model',
                        'created': 1677610602,
                        'owned_by': 'sagemaker'
                    }
                ]
            })
        }

    # Handle OPTIONS (CORS preflight)
    if http_method == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization'
            },
            'body': ''
        }

    # Parse request body
    try:
        if event.get('body'):
            body = event['body']
            if event.get('isBase64Encoded'):
                import base64
                body = base64.b64decode(body).decode('utf-8')
            request_body = json.loads(body)
        else:
            request_body = {}
    except json.JSONDecodeError as e:
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': {'message': f'Invalid JSON: {str(e)}', 'type': 'invalid_request_error'}})
        }

    # Check if endpoint is configured
    if not SAGEMAKER_ENDPOINT_NAME:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': {'message': 'SAGEMAKER_ENDPOINT_NAME not configured', 'type': 'server_error'}})
        }

    try:
        # Determine request format based on path
        if '/chat/completions' in path:
            # OpenAI Chat Completions format - use legacy format for base models
            messages = request_body.get('messages', [])

            # Convert messages to a single prompt for base models
            prompt_parts = []
            for msg in messages:
                role = msg.get('role', 'user')
                content = msg.get('content', '')
                if role == 'system':
                    prompt_parts.append(f"System: {content}")
                elif role == 'assistant':
                    prompt_parts.append(f"Assistant: {content}")
                else:
                    prompt_parts.append(content)

            prompt = '\n'.join(prompt_parts)

            # Build SageMaker request (legacy format for base models)
            sagemaker_payload = {
                'inputs': prompt,
                'parameters': {
                    'max_new_tokens': request_body.get('max_tokens', 100),
                    'temperature': request_body.get('temperature', 0.7),
                    'do_sample': True
                }
            }
        else:
            # Legacy completions format
            sagemaker_payload = {
                'inputs': request_body.get('prompt', ''),
                'parameters': {
                    'max_new_tokens': request_body.get('max_tokens', 100),
                    'temperature': request_body.get('temperature', 0.7),
                    'do_sample': True
                }
            }

        # Invoke SageMaker endpoint
        response = sagemaker_runtime.invoke_endpoint(
            EndpointName=SAGEMAKER_ENDPOINT_NAME,
            ContentType='application/json',
            Body=json.dumps(sagemaker_payload)
        )

        # Parse SageMaker response
        result = json.loads(response['Body'].read().decode('utf-8'))

        # Format response as OpenAI-compatible
        if '/chat/completions' in path:
            # Chat completions response format
            generated_text = result.get('generated_text', '')
            openai_response = {
                'id': f'chatcmpl-{context.aws_request_id}',
                'object': 'chat.completion',
                'created': int(context.get_remaining_time_in_millis() / 1000),
                'model': SAGEMAKER_ENDPOINT_NAME,
                'choices': [
                    {
                        'index': 0,
                        'message': {
                            'role': 'assistant',
                            'content': generated_text
                        },
                        'finish_reason': 'stop'
                    }
                ],
                'usage': {
                    'prompt_tokens': len(prompt.split()),
                    'completion_tokens': len(generated_text.split()),
                    'total_tokens': len(prompt.split()) + len(generated_text.split())
                }
            }
        else:
            # Completions response format
            generated_text = result.get('generated_text', '')
            openai_response = {
                'id': f'cmpl-{context.aws_request_id}',
                'object': 'text_completion',
                'created': int(context.get_remaining_time_in_millis() / 1000),
                'model': SAGEMAKER_ENDPOINT_NAME,
                'choices': [
                    {
                        'index': 0,
                        'text': generated_text,
                        'finish_reason': 'stop'
                    }
                ],
                'usage': {
                    'prompt_tokens': len(request_body.get('prompt', '').split()),
                    'completion_tokens': len(generated_text.split()),
                    'total_tokens': len(request_body.get('prompt', '').split()) + len(generated_text.split())
                }
            }

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(openai_response)
        }

    except sagemaker_runtime.exceptions.ModelError as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': {'message': f'Model error: {str(e)}', 'type': 'model_error'}})
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': {'message': f'Internal error: {str(e)}', 'type': 'server_error'}})
        }
