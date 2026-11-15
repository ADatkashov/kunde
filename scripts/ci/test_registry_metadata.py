import unittest
import urllib.request

from registry_metadata import _DropAuthOnCrossHostRedirect


class RedirectAuthTest(unittest.TestCase):
    def _redirect(self, target):
        request = urllib.request.Request("https://registry-1.docker.io/v2/library/maven/blobs/sha256:abc",
                                         headers={"Authorization": "Bearer secret", "Accept": "application/json"})
        return _DropAuthOnCrossHostRedirect().redirect_request(request, None, 302, "Found", {}, target)

    def test_token_is_not_forwarded_to_another_host(self):
        new = self._redirect("https://production.cloudflare.docker.com/registry-v2/blob")
        self.assertIsNotNone(new)
        self.assertNotIn("authorization", {k.lower() for k in new.headers})
        self.assertNotIn("authorization", {k.lower() for k in new.unredirected_hdrs})
        self.assertEqual(new.get_header("Accept"), "application/json")

    def test_token_is_kept_on_the_same_host(self):
        new = self._redirect("https://registry-1.docker.io/v2/library/maven/blobs/other")
        self.assertEqual(new.get_header("Authorization"), "Bearer secret")


if __name__ == "__main__":
    unittest.main()
