import json
import torch
import logging
from transformers import GPT2Tokenizer, GPT2LMHeadModel

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

def model_fn(model_dir):
    """Load model and tokenizer"""
    logger.info(f"Loading model from {model_dir}")

    # Use explicit class names (not Auto classes) for stability
    tokenizer = GPT2Tokenizer.from_pretrained(model_dir)
    model = GPT2LMHeadModel.from_pretrained(model_dir)

    tokenizer.pad_token = tokenizer.eos_token
    model.eval()

    logger.info("Model loaded successfully")
    return {'model': model, 'tokenizer': tokenizer}

def input_fn(request_body, request_content_type):
    """Parse input data"""
    if request_content_type == 'application/json':
        data = json.loads(request_body)
        return data.get('inputs', data.get('text', ''))
    return str(request_body)

def predict_fn(input_data, model_dict):
    """Generate text"""
    model = model_dict['model']
    tokenizer = model_dict['tokenizer']

    if not input_data or not input_data.strip():
        return "No input provided"

    input_ids = tokenizer.encode(input_data, return_tensors='pt', max_length=512, truncation=True)
    attention_mask = torch.ones_like(input_ids)

    with torch.no_grad():
        output = model.generate(
            input_ids,
            attention_mask=attention_mask,
            max_new_tokens=30,
            temperature=0.8,
            do_sample=True,
            pad_token_id=tokenizer.eos_token_id
        )

    return tokenizer.decode(output[0], skip_special_tokens=True)

def output_fn(prediction, content_type):
    """Format output"""
    return json.dumps({'generated_text': prediction})
