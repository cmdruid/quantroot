"""
Shared fixtures and configuration for Quantroot E2E tests.
"""

import os

import pytest


@pytest.fixture(scope="session")
def base_url():
    """Base URL for service requests."""
    host = os.environ.get("TEST_HOST", "localhost")
    port = os.environ.get("TEST_PORT", "8080")
    return f"http://{host}:{port}"


@pytest.fixture(scope="session")
def stack_config():
    """Stack configuration derived from environment."""
    return {
        "network": os.environ.get("NETWORK", "regtest"),
        "project": "quantroot",
    }
