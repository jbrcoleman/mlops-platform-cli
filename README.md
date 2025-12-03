# ML Platform CLI (mlp)

A developer-friendly CLI tool that simplifies MLOps workflows by abstracting away infrastructure complexity.

## Features

- **Quick Start**: Scaffold ML projects in seconds
- **Experiment Tracking**: Built-in MLflow integration
- **Data Versioning**: DVC-powered data management
- **Easy Deployment**: One-command model deployment to Kubernetes
- **Monitoring**: Real-time model performance tracking
- **Cost Tracking**: Understand your ML infrastructure costs

## Installation

### From Source (Development)

```bash
# Clone the repository
git clone https://github.com/yourusername/mlops-platform-cli.git
cd mlops-platform-cli

# Install in development mode
pip install -e .
```

### From PyPI (Coming Soon)

```bash
pip install mlp-cli
```

## Quick Start

```bash
# Initialize configuration
mlp init

# Deploy local infrastructure (optional)
# mlp deploy-local  # Coming soon

# Create your first experiment
# mlp experiment create my-classifier --framework=sklearn  # Coming soon

# Run training
# cd my-classifier
# mlp experiment run --config=training.yaml  # Coming soon

# Deploy model
# mlp model deploy my-classifier --env=staging  # Coming soon
```

## Tech Stack

- **CLI Framework:** Python with Click
- **Container Orchestration:** Kubernetes (local: kind, cloud: EKS)
- **Experiment Tracking:** MLflow
- **Data Versioning:** DVC
- **ML Pipelines:** Argo Workflows
- **Infrastructure:** Terraform
- **Model Serving:** FastAPI

## Project Status

This is a work in progress. Current implementation status:

- [x] Project structure and setup
- [x] Configuration management
- [x] Init command
- [ ] Experiment management
- [ ] Model registry and deployment
- [ ] Data versioning
- [ ] Pipeline orchestration
- [ ] Monitoring and cost tracking

## Development

### Setting Up Development Environment

```bash
# Install development dependencies
pip install -r requirements-dev.txt

# Run tests
pytest

# Format code
black mlp/

# Type checking
mypy mlp/
```

### Running Tests

```bash
pytest tests/
```

## Documentation

- [Getting Started](docs/getting-started.md) (Coming soon)
- [Command Reference](docs/commands/) (Coming soon)
- [Tutorials](docs/tutorials/) (Coming soon)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details.

## Author

Josh Coleman

## Acknowledgments

Built as a portfolio project to demonstrate platform engineering and MLOps skills.
