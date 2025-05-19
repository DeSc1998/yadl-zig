import pytest
from helper import run_test, load_configs

configurations, file_names = load_configs("test/examples")


@pytest.mark.timeout(10)
@pytest.mark.parametrize("config", configurations, ids=file_names)
def test_config(config):
    run_test(config)
