import pytest

from helper import load_configs, run_failing_test

(configurations, file_names) = load_configs('test/failing')


@pytest.mark.timeout(10)
@pytest.mark.parametrize("config", configurations, ids=file_names)
def test_config(config):
    run_failing_test(config)


def pytest_collection_modifyitems(items):
    for item in items:
        if item.get_marker('timeout') is None:
            item.add_marker(pytest.mark.timeout(10))
