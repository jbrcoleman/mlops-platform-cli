"""Configuration management for ML Platform CLI."""

from pathlib import Path
import yaml
from pydantic import BaseModel, Field
from typing import Optional


class KubernetesConfig(BaseModel):
    """Kubernetes configuration settings."""
    context: str = "kind-mlp"
    namespace: str = "ml-platform"


class MLflowConfig(BaseModel):
    """MLflow configuration settings."""
    tracking_uri: str = "http://localhost:5000"
    artifact_root: str = "s3://mlp-artifacts"


class DVCConfig(BaseModel):
    """DVC configuration settings."""
    remote: str = "s3://mlp-data"


class Config(BaseModel):
    """Main configuration model."""
    kubernetes: KubernetesConfig = Field(default_factory=KubernetesConfig)
    mlflow: MLflowConfig = Field(default_factory=MLflowConfig)
    dvc: DVCConfig = Field(default_factory=DVCConfig)

    @classmethod
    def load(cls) -> "Config":
        """Load configuration from ~/.mlp/config.yaml."""
        config_path = Path.home() / ".mlp" / "config.yaml"
        if config_path.exists():
            with open(config_path) as f:
                data = yaml.safe_load(f)
                if data:
                    return cls(**data)
        return cls()

    def save(self):
        """Save configuration to ~/.mlp/config.yaml."""
        config_path = Path.home() / ".mlp" / "config.yaml"
        config_path.parent.mkdir(parents=True, exist_ok=True)
        with open(config_path, "w") as f:
            yaml.dump(self.model_dump(), f, default_flow_style=False, sort_keys=False)
