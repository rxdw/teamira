"""app/logging_config.py — the JSON-formatting path (audit 3.4.6).
"text" mode (the default) is deliberately a no-op — see
configure_logging's own early return — so there's nothing to assert
about it beyond "it doesn't touch anything," which every other test in
this suite already demonstrates just by running under default settings
without this module ever rearranging their log output.
"""

import json
import logging

from app.config import settings
from app.logging_config import _JsonFormatter, configure_logging


class TestJsonFormatter:
    def test_basic_record_is_valid_json_with_expected_fields(self):
        formatter = _JsonFormatter()
        record = logging.LogRecord(
            name="app.somewhere", level=logging.INFO, pathname=__file__,
            lineno=1, msg="hello %s", args=("world",), exc_info=None,
        )
        parsed = json.loads(formatter.format(record))
        assert parsed["level"] == "INFO"
        assert parsed["logger"] == "app.somewhere"
        assert parsed["message"] == "hello world"
        assert "timestamp" in parsed
        assert "exception" not in parsed

    def test_exception_info_is_included(self):
        formatter = _JsonFormatter()
        try:
            raise ValueError("boom")
        except ValueError:
            import sys
            record = logging.LogRecord(
                name="app.somewhere", level=logging.ERROR, pathname=__file__,
                lineno=1, msg="failed", args=(), exc_info=sys.exc_info(),
            )
        parsed = json.loads(formatter.format(record))
        assert "ValueError: boom" in parsed["exception"]

    def test_output_is_a_single_line(self):
        """A log aggregator reading one JSON object per line breaks the
        moment a single record's formatted output spans more than one
        line — an embedded traceback newline would do exactly that if
        `json.dumps` weren't handling the escaping."""
        formatter = _JsonFormatter()
        try:
            raise ValueError("boom")
        except ValueError:
            import sys
            record = logging.LogRecord(
                name="app.somewhere", level=logging.ERROR, pathname=__file__,
                lineno=1, msg="failed", args=(), exc_info=sys.exc_info(),
            )
        formatted = formatter.format(record)
        assert "\n" not in formatted


class TestConfigureLogging:
    def test_text_mode_is_a_no_op(self):
        original = settings.log_format
        root = logging.getLogger()
        handlers_before = list(root.handlers)
        try:
            settings.log_format = "text"
            configure_logging()
            assert root.handlers == handlers_before
        finally:
            settings.log_format = original

    def test_json_mode_installs_a_json_formatter_on_root(self):
        original = settings.log_format
        try:
            settings.log_format = "json"
            configure_logging()
            root = logging.getLogger()
            assert len(root.handlers) == 1
            assert isinstance(root.handlers[0].formatter, _JsonFormatter)
        finally:
            settings.log_format = original
            # Restore a plain handler so later tests in this same
            # process (pytest runs the whole file in one interpreter)
            # aren't left logging through a formatter meant for JSON
            # mode's console output.
            logging.getLogger().handlers = [logging.StreamHandler()]
