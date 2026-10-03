# Active Storage in production

The app stores two kinds of files through Active Storage: run attachments (`ActionAgent::AgentRun#attachments`) and recording snapshots (`ActionAgent::RecordingSnapshot#file`). Both need storage that every instance can reach and that outlives an instance.

Cloud Run's disk does not qualify:
- It is in memory and counts against the instance's memory limit.
- Only the instance that wrote a file can read it. A run's attachments are uploaded in the web request, but the execution job runs in whichever instance's Solid Queue worker claims it.
- It is gone when the instance stops. Staging scales to zero.

## Choosing the service

The `staging` and `production` Terraform environments both run `RAILS_ENV=production`. `config/environments/production.rb` picks the service with `lib/storage_service_selector.rb`:

| `ACTIVE_STORAGE_SERVICE` | `RECORDINGS_BUCKET` | Service |
|---|---|---|
| unset | set | `google` |
| unset | unset | `local`, with a warning in the boot log |
| `local` | either | `local` |
| `google` | set | `google` |
| `google` | unset | boot fails with a message naming `RECORDINGS_BUCKET` |
| anything else | either | boot fails |

`ACTIVE_STORAGE_SERVICE=local` is for running the production image on a machine with no Google credentials. Development, test and the `sandbox` environment keep using the disk.

The `google` service in `config/storage.yml`:
- authenticates as the Cloud Run service account through Application Default Credentials, so there is no keyfile;
- takes the project from `GOOGLE_CLOUD_PROJECT`, or from the metadata server when that is unset;
- signs download URLs through the IAM Credentials `signBlob` API as `RECORDINGS_SIGNER_EMAIL`.

The signer account can only read the bucket, so a signed URL can download a file but not upload one. Nothing in the app or the engine uses Active Storage direct uploads.

## Turning it on

Terraform creates the bucket, the signer account and their IAM bindings, and passes `RECORDINGS_BUCKET` and `RECORDINGS_SIGNER_EMAIL` to the service and the migrate job only while `enable_recordings_storage` is on. `docs/infrastructure/gcp-cicd-setup.md` describes those resources and the committed `github_app.auto.tfvars` file that holds the flags.

1. Deploy an app version that contains `lib/storage_service_selector.rb`. With the flag off it keeps using the disk.
2. Set `enable_recordings_storage = true` in `terraform/environments/staging/github_app.auto.tfvars` and let the deploy workflow apply it. The new revision boots on `google`, and the boot log no longer carries the disk warning.
3. Check staging:
   - Attach a file to a run, let the service scale to zero, then let the run execute. The job reads the file.
   - `RecordingSnapshot#signed_url` returns a `storage.googleapis.com` URL, and the URL stops working once it expires.
   - An unauthenticated request for an object in the bucket is refused.
4. Repeat step 2 for production.

## Files stored before the switch

Blobs stored on the disk keep `service_name: "local"`. `config/storage.yml` keeps `local` declared because Active Storage raises `KeyError` for a blob whose service is not declared.

Nothing copies those files to the bucket. They lived on an instance's in-memory disk and were lost when that instance stopped, so there is no complete set to copy. Reading one raises `ActiveStorage::FileNotFoundError`, as it already does once its instance has stopped. `ActiveStorage::Blob.where(service_name: "local")` lists them.
