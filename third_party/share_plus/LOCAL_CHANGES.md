# Local share attachment retention

Source: share_plus 13.3.1 from pub.dev, retaining its upstream LICENSE.
Only Android Share.kt cache expiration differs: preparing a share expires
attachments older than ten minutes instead of deleting every earlier URI target.
The application uses unique attachment filenames and clears both source/native
caches on explicit erase. Keep this patch when updating the plugin, or remove
the override once an upstream version provides equivalent retention.

No new plugin, permission or network capability is introduced.
