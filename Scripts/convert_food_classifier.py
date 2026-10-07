#!/usr/bin/env python3
"""Converts the Food-101 EfficientNetV2-S weights to NutriVision/ML/FoodClassifier.mlpackage.

Weights: https://huggingface.co/htetooyan/FoodClassifier (EfficientNetV2S_accuracy_96.pth)
Labels:  the 101 Food-101 classes in alphabetical order (classes.json).

    python3 Scripts/convert_food_classifier.py EfficientNetV2S_accuracy_96.pth classes.json
"""
import json
import sys

import coremltools as ct
import torch
import torch.nn as nn
from torchvision.models import efficientnet_v2_s

weights, classes_path = sys.argv[1], sys.argv[2]
classes = json.load(open(classes_path))
assert len(classes) == 101

model = efficientnet_v2_s(weights=None)
model.classifier[1] = nn.Linear(model.classifier[1].in_features, 101)
state = torch.load(weights, map_location="cpu", weights_only=False)
model.load_state_dict(state.get("model_state_dict", state) if isinstance(state, dict) else state)
model.eval()


class WithSoftmax(nn.Module):
    """Bakes the torchvision preprocessing normalisation and softmax into the graph."""

    def __init__(self, net):
        super().__init__()
        self.net = net
        self.register_buffer("mean", torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1))

    def forward(self, x):  # x: RGB in 0...1
        return torch.softmax(self.net((x - self.mean) / self.std), dim=1)


wrapped = WithSoftmax(model).eval()
example = torch.rand(1, 3, 384, 384)
traced = torch.jit.trace(wrapped, example)

mlmodel = ct.convert(
    traced,
    inputs=[ct.ImageType(name="image", shape=example.shape, scale=1 / 255.0, color_layout=ct.colorlayout.RGB)],
    classifier_config=ct.ClassifierConfig([c.replace("_", " ") for c in classes]),
    minimum_deployment_target=ct.target.iOS17,
    compute_precision=ct.precision.FLOAT16,
    convert_to="mlprogram",
)
mlmodel.short_description = "Food-101 classifier (EfficientNetV2-S)"
mlmodel.save("NutriVision/ML/FoodClassifier.mlpackage")
print("saved")
