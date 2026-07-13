import { useEffect, useRef, useState } from "react"
import { toast } from "sonner"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { ApiError, setDefaultBackend, storeBlob, type BackendInfo } from "@/lib/api"
import { fileToBase64, formatBytes } from "@/lib/blob-utils"

export function UploadCard({
  token,
  backends,
  onStored,
  onBackendsChange,
}: {
  token: string
  backends: BackendInfo | null
  onStored: () => void
  onBackendsChange: (info: BackendInfo) => void
}) {
  const [file, setFile] = useState<File | null>(null)
  const [blobId, setBlobId] = useState("")
  const [backend, setBackend] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [dragging, setDragging] = useState(false)
  const fileInput = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (backends && !backend) setBackend(backends.default)
  }, [backends, backend])

  function pick(next: File) {
    setFile(next)
    setBlobId((current) => current || next.name)
  }

  async function store() {
    if (!file || !blobId.trim() || !backend) return
    setBusy(true)
    try {
      const data = await fileToBase64(file)
      await storeBlob(token, blobId.trim(), data, backend)
      toast.success(`Stored "${blobId.trim()}"`, {
        description: `${formatBytes(file.size)} sent to the ${backend} backend`,
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

  async function makeDefault() {
    if (!backend) return
    try {
      const info = await setDefaultBackend(token, backend)
      onBackendsChange(info)
      toast.success(`${backend} is now your default backend`)
    } catch (error) {
      const message = error instanceof ApiError ? error.message : "Could not set default"
      toast.error(message)
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

        <div className="flex flex-col gap-2">
          <Label htmlFor="backend">Storage backend</Label>
          <div className="flex items-center gap-2">
            <Select value={backend ?? ""} onValueChange={setBackend} disabled={!backends}>
              <SelectTrigger id="backend" className="flex-1 font-mono">
                <SelectValue placeholder="Loading…" />
              </SelectTrigger>
              <SelectContent>
                {backends?.available.map((name) => (
                  <SelectItem key={name} value={name} className="font-mono">
                    {name}
                    {name === backends.default ? " (default)" : ""}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {backends && backend && backend !== backends.default && (
              <Button variant="outline" size="sm" onClick={makeDefault}>
                Make default
              </Button>
            )}
          </div>
          <p className="text-xs text-muted-foreground">
            Where this file's bytes will live. Your default applies when the API gets no explicit
            backend.
          </p>
        </div>

        <Button onClick={store} disabled={!file || !blobId.trim() || !backend || busy}>
          {busy ? "Storing…" : "Store blob"}
        </Button>
      </CardContent>
    </Card>
  )
}
