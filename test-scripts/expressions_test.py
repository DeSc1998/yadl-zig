import pytest
from helper import run_test, load_configs

configurations, file_names = load_configs("test/expressions")


@pytest.mark.parametrize("config", configurations, ids=file_names)
def test_config(config):
    run_test(config)


def pytest_collection_modifyitems(items):
    for item in items:
        if item.get_marker('timeout') is None:
            item.add_marker(pytest.mark.timeout(10))
