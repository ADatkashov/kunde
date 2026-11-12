import tempfile
import unittest
from pathlib import Path

from osv_audit import python_requirements


class PythonRequirementsAuditTests(unittest.TestCase):
    def parse(self, content):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'requirements.txt'
            path.write_text(content)
            return python_requirements(path)

    def test_exact_hashed_python_coordinate_is_audited(self):
        self.assertEqual(self.parse('# native-only\nwebsocket_client==1.9.2 --hash=sha256:' + 'a' * 64),
                         {('PyPI', 'websocket-client', '1.9.2')})

    def test_unsupported_or_empty_requirements_cannot_be_silently_skipped(self):
        for text in ('', '# only comments', 'websocket-client>=1.9.2', '-r other.txt',
                     'websocket-client==1.9.2', 'https://example.invalid/package.whl'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.parse(text)
