import { useRef, useState } from "react"
import { toast } from "sonner"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { ApiError, storeBlob } from "@/lib/api"
import { fileToBase64, formatBytes } from "@/lib/blob-utils"

export function UploadCard({ token, onStored }: { token: string; onStored: () => void }) {
  const [file, setFile] = useState<File | null>(null)
  const [blobId, setBlobId] = useState("")
  const [busy, setBusy] = useState(false)
  const [dragging, setDragging] = useState(false)
  const fileInput = useRef<HTMLInputElement>(null)

  function pick(next: File) {
    setFile(next)
    setBlobId((current) => current || next.name)
  }

  async function store() {
    if (!file || !blobId.trim()) return
    setBusy(true)
    try {
      const data = await fileToBase64(file)
      await storeBlob(token, blobId.trim(), data)
      toast.success(`Stored "${blobId.trim()}"`, {
        description: `${formatBytes(file.size)} sent to the storage backend`,
      })
      setFile(null)
      setBlobId("")
      if (fileInput.current) fileInput.current.value = ""
      onStored()
    } catch (error) {
      const message = error instanceof ApiError ? error.message : "Upload failed"
      toast.error(message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Store a file</CardTitle>
        <CardDescription>
          The file is Base64-encoded and sent to <code className="font-mono">POST /v1/blobs</code>.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <button
          type="button"
          onClick={() => fileInput.current?.click()}
          onDragOver={(e) => {
            e.preventDefault()
            setDragging(true)
          }}
          onDragLeave={() => setDragging(false)}
          onDrop={(e) => {
            e.preventDefault()
            setDragging(false)
            const dropped = e.dataTransfer.files[0]
            if (dropped) pick(dropped)
          }}
          className={`flex min-h-28 cursor-pointer flex-col items-center justify-center gap-1 rounded-md border border-dashed p-6 text-sm transition-colors ${
            dragging ? "border-primary bg-primary/5" : "border-border hover:border-primary/50"
          }`}
        >
          {file ? (
            <>
              <span className="font-medium">{file.name}</span>
              <span className="text-muted-foreground">{formatBytes(file.size)}</span>
            </>
          ) : (
            <>
              <span className="font-medium">Drop a file here</span>
              <span className="text-muted-foreground">or click to browse</span>
            </>
          )}
        </button>
        <input
          ref={fileInput}
          type="file"
          className="hidden"
          onChange={(e) => {
            const chosen = e.target.files?.[0]
            if (chosen) pick(chosen)
          }}
        />

        <div className="flex flex-col gap-2">
          <Label htmlFor="blob-id">Blob id</Label>
          <Input
            id="blob-id"
            className="font-mono"
            placeholder="reports/2026/q3.pdf"
            value={blobId}
            onChange={(e) => setBlobId(e.target.value)}
          />
          <p className="text-xs text-muted-foreground">
            Any unique string — a name, a path, a UUID. It becomes the key you retrieve by.
          </p>
        </div>

        <Button onClick={store} disabled={!file || !blobId.trim() || busy}>
          {busy ? "Storing…" : "Store blob"}
        </Button>
      </CardContent>
    </Card>
  )
}
