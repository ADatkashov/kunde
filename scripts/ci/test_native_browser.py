import json
import unittest
from unittest.mock import Mock, patch

import native_browser as browser


class NativeBrowserTests(unittest.TestCase):
    def test_credentials_are_bound_to_exact_loopback_origin_and_realm(self):
        self.assertTrue(browser.fixture_page('http://localhost:8180/realms/kunde-consumer-check/login-actions/authenticate?session_code=synthetic'))
        for url in ('https://localhost:8180/realms/kunde-consumer-check/',
                    'http://localhost:8181/realms/kunde-consumer-check/',
                    'http://localhost.attacker.test:8180/realms/kunde-consumer-check/',
                    'http://user@localhost:8180/realms/kunde-consumer-check/',
                    'http://localhost:8180/realms/other/'):
            self.assertFalse(browser.fixture_page(url))

    def test_unavailable_form_does_not_submit_credentials(self):
        connection = Mock()
        with patch.object(browser, 'connect', return_value=connection), patch.object(browser, 'evaluate', return_value=False):
            with self.assertRaises(RuntimeError):
                browser.submit('synthetic-user', 'synthetic-password')
        connection.send.assert_not_called()
        connection.close.assert_called_once()

    def test_submit_sends_real_browser_click_only_after_form_check(self):
        connection = Mock()
        with patch.object(browser, 'connect', return_value=connection), patch.object(browser, 'evaluate', return_value=True) as evaluate:
            browser.submit('synthetic-user', 'synthetic-password')
        script = evaluate.call_args.args[1]
        self.assertIn("location.origin !== 'http://localhost:8180'", script)
        message = json.loads(connection.send.call_args.args[0])
        self.assertEqual(message['method'], 'Runtime.evaluate')
        self.assertTrue(message['params']['userGesture'])
        self.assertIn("getElementById('kc-login').click()", message['params']['expression'])
        self.assertNotIn('synthetic-password', message['params']['expression'])
        connection.close.assert_called_once()

    def test_browser_error_does_not_return_exception_text_or_payload(self):
        connection = Mock()
        connection.recv.return_value = json.dumps({'id': 1, 'error': {'message': 'secret-sentinel'}})
        with self.assertRaisesRegex(RuntimeError, '^Browser evaluation failed$'):
            browser.evaluate(connection, 'document.readyState')


    def test_registration_refuses_unavailable_form(self):
        connection = Mock()
        with patch.object(browser, 'connect', return_value=connection), patch.object(browser, 'evaluate', return_value=False):
            with self.assertRaisesRegex(RuntimeError, '^Fixture registration form unavailable$'):
                browser.register('native-synthetic', 'secret-sentinel', 'different')
        connection.send.assert_not_called()
        connection.close.assert_called_once()

    def test_registration_click_has_user_gesture_without_secrets(self):
        connection = Mock()
        with patch.object(browser, 'connect', return_value=connection), patch.object(browser, 'evaluate', return_value=True) as evaluate:
            browser.register('native-synthetic', 'secret-sentinel', 'different')
        script = evaluate.call_args.args[1]
        self.assertIn("new URL(form.action).origin !== location.origin", script)
        self.assertIn("field.type !== 'password'", script)
        message = json.loads(connection.send.call_args.args[0])
        self.assertTrue(message['params']['userGesture'])
        self.assertNotIn('secret-sentinel', message['params']['expression'])
        connection.close.assert_called_once()
