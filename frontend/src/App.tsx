import { useCallback, useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import { BlobTable } from "@/components/blob-table"
import { UploadCard } from "@/components/upload-card"
import { ApiError, getBackends, listBlobs, type BackendInfo, type BlobMeta } from "@/lib/api"
import { useTheme } from "@/lib/theme"
import { DatabaseIcon, ExternalLinkIcon, MoonIcon, SunIcon } from "lucide-react"

const MINIO_CONSOLE = import.meta.env.VITE_MINIO_CONSOLE ?? "http://localhost:9001"

export default function App() {
  const [token, setToken] = useState(() => localStorage.getItem("simple-drive-token") ?? "dev-token")
  const [blobs, setBlobs] = useState<BlobMeta[]>([])
  const [backends, setBackends] = useState<BackendInfo | null>(null)
  const [error, setError] = useState<string | null>(null)
  const { theme, toggle } = useTheme()

  const refresh = useCallback(async () => {
    try {
      const [blobList, backendInfo] = await Promise.all([listBlobs(token), getBackends(token)])
      setBlobs(blobList)
      setBackends(backendInfo)
      setError(null)
    } catch (err) {
      setBlobs([])
      setBackends(null)
      setError(
        err instanceof ApiError && err.status === 401
          ? "Unauthorized — check the API token."
          : err instanceof ApiError
            ? err.message
            : "Something went wrong."
      )
    }
  }, [token])

  useEffect(() => {
    localStorage.setItem("simple-drive-token", token)
    const timer = setTimeout(refresh, 300)
    return () => clearTimeout(timer)
  }, [token, refresh])

  return (
    <div className="mx-auto flex min-h-screen max-w-6xl flex-col gap-6 px-6 py-8">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="flex size-10 items-center justify-center rounded-md bg-primary text-primary-foreground">
            <DatabaseIcon className="size-5" />
          </div>
          <div>
            <h1 className="text-xl font-semibold tracking-tight">Simple Drive</h1>
            <p className="font-mono text-xs text-muted-foreground">
              one API · swappable storage backends
            </p>
          </div>
        </div>

        <div className="flex items-end gap-3">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="token" className="text-xs">
              API token
            </Label>
            <Input
              id="token"
              className="h-8 w-44 font-mono text-sm"
              value={token}
              onChange={(e) => setToken(e.target.value)}
            />
          </div>
          <Button
            variant="outline"
            size="sm"
            render={<a href={MINIO_CONSOLE} target="_blank" rel="noreferrer" />}
          >
            MinIO console
            <ExternalLinkIcon />
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={toggle}
            aria-label={theme === "dark" ? "Switch to light mode" : "Switch to dark mode"}
          >
            {theme === "dark" ? <SunIcon /> : <MoonIcon />}
          </Button>
        </div>
      </header>

      <Separator />

      {error && (
        <div className="rounded-md border border-destructive/30 bg-destructive/5 px-4 py-3 text-sm text-destructive">
          {error}
        </div>
      )}

      <main className="grid gap-6 lg:grid-cols-[minmax(20rem,2fr)_5fr]">
        <UploadCard
          token={token}
          backends={backends}
          onStored={refresh}
          onBackendsChange={setBackends}
        />
        <BlobTable token={token} blobs={blobs} />
      </main>
    </div>
  )
}
