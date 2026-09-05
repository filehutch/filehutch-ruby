// FileHutch browser-direct upload.
//
// The bytes go from the browser straight to storage; only two small JSON calls
// hit your Rails app (mounted FileHutch::Engine), which holds the API key.
//
// Stimulus usage (register as "filehutch-direct-upload"):
//
//   <div data-controller="filehutch-direct-upload"
//        data-filehutch-direct-upload-url-value="/file_hutch/uploads"
//        data-filehutch-direct-upload-policy-value="avatars">
//     <input type="file" data-action="filehutch-direct-upload#upload">
//     <input type="hidden" name="user[avatar_file_id]" data-filehutch-direct-upload-target="fileId">
//     <progress value="0" max="100" hidden data-filehutch-direct-upload-target="progress"></progress>
//     <p data-filehutch-direct-upload-target="status"></p>
//   </div>
//
// Events on the element: filehutch:start, filehutch:progress ({percent}), filehutch:complete ({file}),
// filehutch:error ({error}). The surrounding form's submit buttons are disabled while uploading.

import { Controller } from "@hotwired/stimulus"

export class DirectUploadError extends Error {
  constructor(message, { code, status } = {}) {
    super(message)
    this.name = "DirectUploadError"
    this.code = code
    this.status = status
  }
}

// Framework-neutral: returns the ready file object.
export async function directUpload(file, { url, policy, csrfToken, onProgress } = {}) {
  if (!url) throw new DirectUploadError("directUpload needs a url")
  if (!policy) throw new DirectUploadError("directUpload needs a policy")

  const created = await postJSON(url, {
    policy,
    filename: file.name,
    content_type: file.type || "application/octet-stream",
    byte_size: file.size
  }, csrfToken)

  await putToStorage(created.upload, file, onProgress)

  const completed = await postJSON(`${url.replace(/\/$/, "")}/${created.upload.id}/complete`, {}, csrfToken)
  return completed.file
}

function putToStorage(upload, file, onProgress) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest()
    xhr.open(upload.method || "PUT", upload.url, true)
    Object.entries(upload.headers || {}).forEach(([name, value]) => xhr.setRequestHeader(name, value))
    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable && onProgress) onProgress(Math.round((event.loaded / event.total) * 100))
    }
    xhr.onload = () => (xhr.status >= 200 && xhr.status < 300)
      ? resolve()
      : reject(new DirectUploadError(`Storage rejected the upload (HTTP ${xhr.status})`, { code: "storage_rejected", status: xhr.status }))
    xhr.onerror = () => reject(new DirectUploadError("Network error talking to storage (check bucket CORS)", { code: "network" }))
    xhr.send(file)
  })
}

async function postJSON(url, body, csrfToken) {
  const headers = { "Content-Type": "application/json", "Accept": "application/json" }
  const token = csrfToken || document.querySelector("meta[name='csrf-token']")?.content
  if (token) headers["X-CSRF-Token"] = token
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify(body), credentials: "same-origin" })
  const data = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new DirectUploadError(data.error?.message || `Request failed (HTTP ${response.status})`, { code: data.error?.code, status: response.status })
  }
  return data
}

export default class extends Controller {
  static targets = ["fileId", "progress", "status"]
  static values = { url: { type: String, default: "/file_hutch/uploads" }, policy: String }

  async upload(event) {
    const file = event.target.files?.[0]
    if (!file) return

    this.busy(true)
    this.dispatch("start", { detail: { file } })
    try {
      const uploaded = await directUpload(file, {
        url: this.urlValue,
        policy: this.policyValue,
        onProgress: (percent) => this.progress(percent)
      })
      if (this.hasFileIdTarget) this.fileIdTarget.value = uploaded.id
      this.note(`${uploaded.filename} uploaded`)
      this.dispatch("complete", { detail: { file: uploaded } })
    } catch (error) {
      if (this.hasFileIdTarget) this.fileIdTarget.value = ""
      this.note(error.message, true)
      this.dispatch("error", { detail: { error } })
    } finally {
      this.busy(false)
    }
  }

  busy(state) {
    this.submitButtons.forEach((button) => { button.disabled = state })
    if (this.hasProgressTarget) {
      this.progressTarget.hidden = !state
      if (state) this.progress(0)
    }
    this.element.dataset.filehutchUploading = state ? "true" : "false"
  }

  progress(percent) {
    if (this.hasProgressTarget) this.progressTarget.value = percent
    this.dispatch("progress", { detail: { percent } })
  }

  note(message, isError = false) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    this.statusTarget.dataset.filehutchState = isError ? "error" : "ok"
  }

  get submitButtons() {
    const form = this.element.closest("form")
    return form ? Array.from(form.querySelectorAll("button[type=submit], input[type=submit]")) : []
  }
}
