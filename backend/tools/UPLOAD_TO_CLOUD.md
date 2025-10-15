Upload cached previews to cloud (S3 / Google Drive)

Options provided in this repo:

1) AWS S3 uploader (Python) - `tools/upload_cache_to_s3.py`
   - Requires `boto3` (pip install boto3)
   - Uses AWS credentials via env vars or `~/.aws/credentials`
   - Example (dry-run):

     python tools/upload_cache_to_s3.py --bucket my-bucket --prefix previews/ --dry-run

   - Example (upload and delete local):

     python tools/upload_cache_to_s3.py --bucket my-bucket --prefix previews/ --delete-after

2) Google Drive / Google Cloud Storage via rclone (recommended for Drive interoperability)
   - Install rclone: https://rclone.org/install/
   - Configure remote (interactive):

     rclone config

     # Create a remote name, e.g. 'gdrive' and follow prompts to authorize

   - Copy files to Drive folder (example):

     # Copy entire cache folder
     rclone copy C:\musicapp\backend\app\static\audio\deezer gdrive:MusicApp/previews --progress

   - Or use Google Cloud Storage (gcs) remote and lifecycle rules for auto-delete

3) Notes & best practices
   - Use server-side storage (S3/GCS) for production; Google Drive is fine for ad-hoc backups but lacks lifecycle controls unless layered.
   - If files contain copyrighted content, ensure you respect Deezer's terms; prefer short-term cache not permanent public hosting.
   - Consider using signed URLs from your cloud provider for serving to clients if you want to offload delivery.

If you want, I can:
 - Run the S3 upload here (you must provide AWS credentials or allow me to use a profile), or
 - Provide the exact rclone commands for Google Drive and optionally create a small PowerShell script to run periodically.
