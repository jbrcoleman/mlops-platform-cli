from setuptools import setup, find_packages

setup(
    name="mlp",
    version="0.1.0",
    packages=find_packages(),
    install_requires=[
        "click>=8.1.0",
        "rich>=13.0.0",        # Beautiful terminal output
        "pyyaml>=6.0",
        "kubernetes>=28.0.0",
        "mlflow>=2.9.0",
        "dvc>=3.0.0",
        "boto3>=1.28.0",       # AWS SDK
        "requests>=2.31.0",
        "jinja2>=3.1.0",       # For templates
        "pydantic>=2.0.0",     # Config validation
    ],
    entry_points={
        "console_scripts": [
            "mlp=mlp.cli:cli",
        ],
    },
    python_requires=">=3.10",
    author="Your Name",
    description="ML Platform CLI - Simplify your MLOps workflows",
    long_description=open("README.md").read(),
    long_description_content_type="text/markdown",
)
