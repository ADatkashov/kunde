import json
import unittest
import xml.etree.ElementTree as ET

from consumer_native_e2e import center, editable, find_label, safe_diagnostics
from native_identity_stack import realm_fixture


def node(**attributes):
    return ET.Element("node", {"bounds": "[10,20][110,60]", "enabled": "true", **attributes})


class NativeFixtureTests(unittest.TestCase):
    def test_fixture_retains_public_pkce_and_no_password_grants(self):
        realm = realm_fixture("synthetic-user", "unit-fixture-only", "synthetic-subject")
        client = next(c for c in realm["clients"] if c["clientId"] == "kunde-consumer")
        self.assertTrue(client["publicClient"])
        self.assertTrue(client["standardFlowEnabled"])
        self.assertFalse(client["directAccessGrantsEnabled"])
        self.assertFalse(client["implicitFlowEnabled"])
        self.assertEqual(client["attributes"]["pkce.code.challenge.method"], "S256")
        self.assertEqual(realm["refreshTokenMaxReuse"], 0)
        self.assertEqual(realm["accessTokenLifespan"], 300)
        self.assertTrue(realm["users"][0]["email"].endswith("@example.invalid"))

    def test_bounds_reject_empty_or_malformed_targets(self):
        self.assertEqual(center(node()), (60, 40))
        self.assertIsNone(center(node(bounds="[0,0][0,0]")))
        self.assertIsNone(center(node(bounds="invalid")))

    def test_labels_select_button_not_login_heading(self):
        tree = ET.Element("hierarchy")
        tree.append(node(text="Sign in to your account", package="com.android.chrome"))
        button = node(text="Sign In", package="com.android.chrome")
        tree.append(button)
        self.assertIs(find_label(tree, ["Sign in"], "com.android.chrome"), button)
        self.assertIsNone(find_label(tree, ["Sign in"], "other.package"))

    def test_editable_excludes_browser_url_and_does_not_guess_ambiguous_fields(self):
        tree = ET.Element("hierarchy")
        tree.append(node(**{"class": "android.widget.EditText", "resource-id": "com.android.chrome:id/url_bar"}))
        user = node(**{"class": "android.widget.EditText", "resource-id": "username"})
        password = node(**{"class": "android.widget.EditText", "password": "true"})
        tree.extend([user, password])
        self.assertIs(editable(tree), user)
        self.assertIs(editable(tree, True), password)
        tree.append(node(**{"class": "android.widget.EditText"}))
        self.assertIsNone(editable(tree))

    def test_diagnostics_never_emit_arbitrary_ui_text_or_credentials(self):
        tree = ET.Element("hierarchy")
        tree.append(node(text="password-sentinel", **{"class": "android.widget.EditText", "password": "true"}))
        tree.append(node(**{"content-desc": "http://localhost/callback?code=secret-sentinel"}))
        tree.append(node(text="Profile"))
        report = json.dumps(safe_diagnostics(tree))
        self.assertIn("Profile", report)
        self.assertNotIn("password-sentinel", report)
        self.assertNotIn("secret-sentinel", report)
        self.assertNotIn("callback", report)
