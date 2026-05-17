IMAGE = ghcr.io/soliddowant/openarc-asr

# Tags mirror the flake's attribute keys (see flake.nix `models`).
MODELS = \
	whisper-large-v3-int8 \
	whisper-large-v3-fp16 \
	distil-whisper-large-v3-int8 \
	distil-whisper-large-v3-fp16 \
	qwen3-asr-0_6b-int8-asym

.PHONY: all
all: $(addprefix image-,$(MODELS))

.PHONY: image-%
image-%:
	$$(nix build --print-out-paths --no-link .#image-$*) | docker load
	docker tag openarc-asr:$* $(IMAGE):$*
	docker push $(IMAGE):$*
