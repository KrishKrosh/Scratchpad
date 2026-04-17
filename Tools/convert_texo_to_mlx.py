#!/usr/bin/env python3

import argparse
import json
from pathlib import Path

import torch
from safetensors.torch import load_file
from safetensors.torch import save_file


def to_stage_list(stage_config: dict) -> list[dict]:
    stages = []
    for key in sorted(stage_config.keys()):
        values = stage_config[key]
        stages.append(
            {
                "inChannels": values[0],
                "midChannels": values[1],
                "outChannels": values[2],
                "blockCount": values[3],
                "layerCount": values[4],
                "kernelSize": values[5],
                "downsample": values[6],
                "lightBlock": values[7],
            }
        )
    return stages


def convert_state_dict(state_dict: dict[str, torch.Tensor]) -> dict[str, torch.Tensor]:
    converted: dict[str, torch.Tensor] = {}
    for name, tensor in state_dict.items():
        if name.endswith("num_batches_tracked"):
            continue
        if tensor.ndim == 4 and (
            ".conv.weight" in name
            or name.endswith(".stem1.conv.weight")
            or name.endswith(".stem2a.conv.weight")
            or name.endswith(".stem2b.conv.weight")
            or name.endswith(".stem3.conv.weight")
            or name.endswith(".stem4.conv.weight")
        ):
            converted[name] = tensor.permute(0, 2, 3, 1).contiguous()
        else:
            converted[name] = tensor.contiguous()
    return converted


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", required=True, help="Path to Texo checkpoint .pt/.bin/.safetensors converted into state_dict keys")
    parser.add_argument("--tokenizer", required=True, help="Path to Texo tokenizer.json")
    parser.add_argument("--output", required=True, help="Output directory for MLX-ready model files")
    parser.add_argument("--config", help="Optional JSON file containing the Texo model config")
    args = parser.parse_args()

    output_dir = Path(args.output).expanduser()
    output_dir.mkdir(parents=True, exist_ok=True)

    checkpoint_path = Path(args.checkpoint).expanduser()
    if checkpoint_path.suffix == ".safetensors":
        state_dict = load_file(str(checkpoint_path), device="cpu")
    else:
        state_dict = torch.load(checkpoint_path, map_location="cpu")
        if "state_dict" in state_dict:
            state_dict = state_dict["state_dict"]
    state_dict = {k.removeprefix("model."): v for k, v in state_dict.items()}
    converted = convert_state_dict(state_dict)

    if args.config:
        model_config = json.loads(Path(args.config).expanduser().read_text())
    elif checkpoint_path.parent.joinpath("config.json").exists():
        model_config = json.loads(checkpoint_path.parent.joinpath("config.json").read_text())
    else:
        model_config = {
            "stemChannels": [3, 32, 48],
            "stages": [
                {"inChannels": 48, "midChannels": 48, "outChannels": 128, "blockCount": 1, "layerCount": 6, "kernelSize": 3, "downsample": False, "lightBlock": False},
                {"inChannels": 128, "midChannels": 96, "outChannels": 512, "blockCount": 1, "layerCount": 6, "kernelSize": 3, "downsample": True, "lightBlock": False},
                {"inChannels": 512, "midChannels": 192, "outChannels": 1024, "blockCount": 3, "layerCount": 6, "kernelSize": 5, "downsample": True, "lightBlock": True},
                {"inChannels": 1024, "midChannels": 384, "outChannels": 2048, "blockCount": 1, "layerCount": 6, "kernelSize": 5, "downsample": True, "lightBlock": True},
            ],
            "encoderHiddenSize": 2048,
            "vocabSize": 687,
            "maxPositionEmbeddings": 1027,
            "positionOffset": 2,
            "dModel": 384,
            "decoderLayerCount": 2,
            "decoderAttentionHeads": 16,
            "decoderFFNDim": 1536,
            "bosTokenID": 0,
            "padTokenID": 1,
            "eosTokenID": 2,
            "maxDecodeLength": 256,
            "layerNormEps": 1e-5,
            "scaleEmbedding": True,
            "imageSize": 384,
        }

    if "encoder" in model_config and "decoder" in model_config:
        model_config = {
            "imageSize": 384,
            "stemChannels": model_config["encoder"]["stem_channels"],
            "stages": to_stage_list(model_config["encoder"]["stage_config"]),
            "encoderHiddenSize": model_config["encoder"]["hidden_size"],
            "vocabSize": model_config["decoder"]["vocab_size"],
            "maxPositionEmbeddings": model_config["decoder"]["max_position_embeddings"],
            "positionOffset": 2,
            "dModel": model_config["decoder"]["d_model"],
            "decoderLayerCount": model_config["decoder"]["decoder_layers"],
            "decoderAttentionHeads": model_config["decoder"]["decoder_attention_heads"],
            "decoderFFNDim": model_config["decoder"]["decoder_ffn_dim"],
            "bosTokenID": model_config["decoder"]["bos_token_id"],
            "padTokenID": model_config["decoder"]["pad_token_id"],
            "eosTokenID": model_config["decoder"]["eos_token_id"],
            "maxDecodeLength": 256,
            "layerNormEps": model_config["decoder"]["layer_norm_eps"],
            "scaleEmbedding": model_config["decoder"].get("scale_embedding", True),
        }

    save_file(converted, output_dir / "weights.safetensors")
    (output_dir / "config.json").write_text(json.dumps(model_config, indent=2))
    tokenizer_src = Path(args.tokenizer).expanduser()
    (output_dir / "tokenizer.json").write_text(tokenizer_src.read_text())


if __name__ == "__main__":
    main()
