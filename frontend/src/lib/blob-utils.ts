export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  const units = ["KB", "MB", "GB"]
  let value = bytes
  let unit = "B"
  for (const next of units) {
    if (value < 1024) break
    value /= 1024
    unit = next
  }
  return `${value.toFixed(value >= 100 ? 0 : 1)} ${unit}`
}

// SHA-256 hex of the blob id — the exact key the backend stores the object
// under (see Storage::Base#key_for), so the UI can point at the real object.
export async function storageKey(id: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(id))
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
}

export function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve((reader.result as string).split(",")[1] ?? "")
    reader.onerror = () => reject(reader.error)
    reader.readAsDataURL(file)
  })
}

export function downloadBase64(id: string, base64: string) {
  const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0))
  const url = URL.createObjectURL(new Blob([bytes]))
  const anchor = document.createElement("a")
  anchor.href = url
  anchor.download = id.split("/").pop() || id
  anchor.click()
  URL.revokeObjectURL(url)
}
