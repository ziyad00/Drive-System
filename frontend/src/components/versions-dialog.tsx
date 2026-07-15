import { useEffect, useState } from "react"
import { toast } from "sonner"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { ApiError, listVersions, restoreVersion, type FileVersion, type TreeNode } from "@/lib/api"
import { formatBytes } from "@/lib/blob-utils"
import { HistoryIcon } from "lucide-react"

export function VersionsDialog({
  token,
  node,
  onClose,
  onRestored,
}: {
  token: string
  node: TreeNode | null
  onClose: () => void
  onRestored: () => void
}) {
  const [versions, setVersions] = useState<FileVersion[] | null>(null)

  useEffect(() => {
    if (!node) return
    setVersions(null)
    listVersions(token, node.id)
      .then(setVersions)
      .catch(() => toast.error("Could not load versions"))
  }, [token, node])

  async function restore(version: FileVersion) {
    if (!node) return
    try {
      await restoreVersion(token, node.id, version.id)
      toast.success(`Restored ${node.name} to the version from ${new Date(version.created_at).toLocaleString()}`)
      onRestored()
      onClose()
    } catch (error) {
      toast.error(error instanceof ApiError ? error.message : "Restore failed")
    }
  }

  return (
    <Dialog open={!!node} onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <HistoryIcon className="size-4" />
            Versions of {node?.name}
          </DialogTitle>
          <DialogDescription>
            Restoring swaps a version back in; the current content joins the history.
          </DialogDescription>
        </DialogHeader>

        {versions === null ? (
          <p className="py-4 text-sm text-muted-foreground">Loading…</p>
        ) : versions.length === 0 ? (
          <p className="py-4 text-sm text-muted-foreground">
            No previous versions — history appears when the file's content is replaced.
          </p>
        ) : (
          <ul className="flex flex-col divide-y">
            {versions.map((version) => (
              <li key={version.id} className="flex items-center justify-between gap-3 py-2">
                <div className="flex flex-col">
                  <span className="text-sm">{new Date(version.created_at).toLocaleString()}</span>
                  <span className="font-mono text-xs text-muted-foreground">
                    {formatBytes(Number(version.size))} · {version.backend}
                  </span>
                </div>
                <Button size="sm" variant="outline" onClick={() => restore(version)}>
                  Restore
                </Button>
              </li>
            ))}
          </ul>
        )}
      </DialogContent>
    </Dialog>
  )
}
