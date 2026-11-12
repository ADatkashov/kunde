import json
import unittest
from unittest.mock import patch, Mock
import xml.etree.ElementTree as ET

from consumer_native_e2e import Scenario, center, editable, find_label, safe_diagnostics, network_diagnostics
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

    def test_network_diagnostics_drop_raw_logs_urls_and_response_bodies(self):
        response = Mock()
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        response.read.return_value = b'[{"type":"page","url":"http://localhost/callback?code=secret-sentinel","title":"password-sentinel"}]'
        opener = Mock()
        opener.open.return_value = response
        with patch("consumer_native_e2e.subprocess.run", return_value=Mock(
                returncode=0, stdout=b"HTTP/1.0 200 OK\r\npassword-sentinel", stderr=b"")), \
             patch("consumer_native_e2e.adb", return_value=b"net::ERR_CONNECTION_REFUSED secret-sentinel"), \
             patch("consumer_native_e2e.urllib.request.build_opener", return_value=opener):
            report = json.dumps(network_diagnostics())
        self.assertIn("ERR_CONNECTION_REFUSED", report)
        self.assertIn("fixture", report)
        self.assertNotIn("password-sentinel", report)
        self.assertNotIn("secret-sentinel", report)
        self.assertNotIn("callback", report)


    def test_provider_outage_restores_reverse_even_on_failed_assertion(self):
        scenario = Scenario({})
        with patch("consumer_native_e2e.adb") as adb_call, \
             patch("consumer_native_e2e.network_diagnostics", return_value={"8180": {"httpStatus": 200}}):
            with self.assertRaisesRegex(AssertionError, "unreachable"):
                scenario.provider_network_recovery()
        self.assertEqual(adb_call.call_args_list[0].args, ("reverse", "--remove", "tcp:8180"))
        self.assertEqual(adb_call.call_args_list[-1].args, ("reverse", "tcp:8180", "tcp:8180"))
        self.assertEqual(scenario.completed, [])

    def test_provider_recovery_requires_real_device_probe_and_profile(self):
        scenario = Scenario({})
        with patch("consumer_native_e2e.adb"), \
             patch("consumer_native_e2e.network_diagnostics", side_effect=[
                 {"8180": {"httpStatus": None}}, {"8180": {"httpStatus": 200}}]), \
             patch.object(scenario, "profile") as profile:
            scenario.provider_network_recovery()
        profile.assert_called_once()
        self.assertEqual(len(scenario.completed), 1)

    def test_registration_binding_count_excludes_backend_test_issuers(self):
        scenario = Scenario({'marker': 'kunde-native-012345abcdef'})
        with patch('consumer_native_e2e.docker', return_value='1') as execute:
            self.assertEqual(scenario.binding_count(), 1)
        query = execute.call_args.args[-1]
        self.assertIn("WHERE issuer='http://localhost:8180/realms/kunde-consumer-check'", query)

    def test_registered_profile_query_excludes_seed_subject(self):
        scenario = Scenario({'marker': 'kunde-native-012345abcdef',
                             'subject': '11111111-1111-4111-8111-111111111111'})
        response = json.dumps({'id': '22222222-2222-4222-8222-222222222222',
                               'subject': '33333333-3333-4333-8333-333333333333'})
        with patch('consumer_native_e2e.docker', return_value=response) as execute:
            profile = scenario.db_profile(registered=True)
        self.assertEqual(profile['subject'], '33333333-3333-4333-8333-333333333333')
        query = execute.call_args.args[-1]
        self.assertIn("AND b.subject<>'11111111-1111-4111-8111-111111111111'", query)
        self.assertIn("b.issuer='http://localhost:8180/realms/kunde-consumer-check'", query)

    def test_registered_profile_rejects_multiple_canonical_bindings(self):
        scenario = Scenario({'marker': 'kunde-native-012345abcdef',
                             'subject': '11111111-1111-4111-8111-111111111111'})
        with patch('consumer_native_e2e.docker', return_value='\n'.join(['{}', '{}'])):
            with self.assertRaisesRegex(AssertionError, 'Expected one canonical synthetic identity'):
                scenario.db_profile(registered=True)

    def test_registered_profile_rejects_untrusted_subject_before_sql(self):
        scenario = Scenario({'marker': 'kunde-native-012345abcdef',
                             'subject': "anything' OR true --"})
        with patch('consumer_native_e2e.docker') as execute:
            with self.assertRaisesRegex(ValueError, 'Unexpected synthetic subject'):
                scenario.db_profile(registered=True)
        execute.assert_not_called()


class SessionFailurePathTests(unittest.TestCase):
    saved = {"id": "x", "name": "NativeValidated"}

    def test_outage_during_refresh_restores_reverse_and_requires_retry_without_relogin(self):
        scenario = Scenario({})
        with patch("consumer_native_e2e.adb") as adb_call, \
             patch.object(scenario, "app_label", side_effect=TimeoutError()):
            with self.assertRaises(TimeoutError):
                scenario.provider_outage_during_refresh(self.saved)
        self.assertEqual(adb_call.call_args_list[-1].args, ("reverse", "tcp:8180", "tcp:8180"))
        self.assertEqual(scenario.completed, [])

    def test_outage_recovery_asserts_canonical_profile_unchanged(self):
        scenario = Scenario({})
        with patch("consumer_native_e2e.adb"), patch.object(scenario, "app_label"), \
             patch.object(scenario, "tap_label"), patch.object(scenario, "profile"), \
             patch.object(scenario, "db_profile", return_value={"id": "other"}):
            with self.assertRaisesRegex(AssertionError, "canonical"):
                scenario.provider_outage_during_refresh(self.saved)

    def test_replay_restores_snapshot_taken_before_rotation_and_requires_expired_ui(self):
        scenario = Scenario({"marker": "kunde-native-012345abcdef"})
        order = []
        with patch.object(scenario, "vault_snapshot", side_effect=lambda: order.append("snapshot") or b"opaque"), \
             patch.object(scenario, "launch", side_effect=lambda: order.append("launch")), \
             patch.object(scenario, "profile", side_effect=lambda: order.append("rotate")), \
             patch.object(scenario, "vault_restore", side_effect=lambda data: order.append(("restore", data))), \
             patch.object(scenario, "app_label", side_effect=lambda label: order.append(label)), \
             patch.object(scenario, "sign_in_again"), patch.object(scenario, "binding_count", return_value=1), \
             patch.object(scenario, "db_profile", return_value=self.saved):
            scenario.refresh_replay(self.saved)
        self.assertEqual(order[:5], ["snapshot", "launch", "rotate", ("restore", b"opaque"), "launch"])
        self.assertEqual(order[5], "Your session expired. Sign in again.")
        self.assertEqual(len(scenario.completed), 1)

    def test_replay_fails_if_relogin_changes_account(self):
        scenario = Scenario({})
        with patch.object(scenario, "vault_snapshot", return_value=b"x"), patch.object(scenario, "launch"), \
             patch.object(scenario, "profile"), patch.object(scenario, "vault_restore"), \
             patch.object(scenario, "app_label"), patch.object(scenario, "sign_in_again"), \
             patch.object(scenario, "binding_count", return_value=2), \
             patch.object(scenario, "db_profile", return_value=self.saved):
            with self.assertRaisesRegex(AssertionError, "canonical"):
                scenario.refresh_replay(self.saved)

    def test_vault_file_requires_single_secure_storage_file(self):
        scenario = Scenario({})
        with patch("consumer_native_e2e.adb", return_value=b"FlutterSecureStorage.xml\nother.xml\n"):
            self.assertEqual(scenario.vault_file(), "shared_prefs/FlutterSecureStorage.xml")
        with patch("consumer_native_e2e.adb", return_value=b"other.xml\n"):
            with self.assertRaises(AssertionError):
                scenario.vault_file()

    def test_expiry_always_restores_clock_and_records_unavailable_control(self):
        scenario = Scenario({})
        epochs = iter([1000, 1000, 1000])
        with patch("consumer_native_e2e.adb"), patch.object(scenario, "device_epoch", side_effect=lambda: next(epochs)), \
             patch.object(scenario, "set_clock") as clock:
            scenario.access_token_expiry()
        self.assertEqual(clock.call_args_list[-1].args, (400,))
        self.assertEqual(scenario.completed, [])
        self.assertEqual(len(scenario.not_executed), 1)

    def test_token_secrecy_detects_jwt_in_log_or_vault_without_echoing_it(self):
        scenario = Scenario({})
        jwt = b"eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJzZWNyZXQifQ.signature"
        with patch.object(scenario, "vault_file", return_value="shared_prefs/FlutterSecureStorage.xml"), \
             patch("consumer_native_e2e.adb", side_effect=[b"log " + jwt, b"vault"]):
            with self.assertRaises(AssertionError) as raised:
                scenario.token_secrecy()
        self.assertNotIn("eyJ", str(raised.exception))
        with patch.object(scenario, "vault_file", return_value="shared_prefs/FlutterSecureStorage.xml"), \
             patch("consumer_native_e2e.adb", side_effect=[b"clean", b"opaque"]):
            scenario.token_secrecy()
        self.assertEqual(len(scenario.completed), 1)
