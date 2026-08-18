from unittest.mock import patch

from django.core.exceptions import ImproperlyConfigured
from django.test import SimpleTestCase

from config.plugins import enabled_plugin_names, plugin_urlpatterns


class OptionalPluginRegistryTests(SimpleTestCase):
    def test_core_has_no_optional_plugins_by_default(self):
        self.assertEqual(enabled_plugin_names(''), ())

    def test_rbac_is_opt_in_and_mounts_only_when_enabled(self):
        with patch.dict('os.environ', {'ANTIQ_BACKEND_PLUGINS': 'rbac'}, clear=False):
            patterns = list(plugin_urlpatterns())
        self.assertEqual(len(patterns), 1)
        self.assertEqual(str(patterns[0].pattern), 'api/rbac/')

    def test_unknown_plugin_blocks_startup(self):
        with self.assertRaises(ImproperlyConfigured):
            enabled_plugin_names('rbac,unknown-plugin')
