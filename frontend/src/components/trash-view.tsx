import { useCallback, useEffect, useState } from "react"
import { toast } from "sonner"
import { Button } from "@/components/ui/button"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import {
  ApiError,
  emptyTrash,
  listTrash,
  purgeTrash,
  restoreTrash,
  type TrashEntry,
} from "@/lib/api"
import { FileIcon, FolderIcon, Trash2Icon, Undo2Icon, XIcon } from "lucide-react"

export function TrashView({
  token,
  refreshSignal,
  onRestored,
}: {
  token: string
  refreshSignal: number
  onRestored: () => void
}) {
  const [entries, setEntries] = useState<TrashEntry[]>([])

  const refresh = useCallback(async () => {
    try {
      setEntries(await listTrash(token))
    } catch {
      setEntries([])
    }
  }, [token])

  useEffect(() => {
    refresh()
  }, [refresh, refreshSignal])

  async function restore(entry: TrashEntry) {
    try {
      await restoreTrash(token, entry.id)
      toast.success(`Restored ${entry.name}`)
      refresh()
      onRestored()
    } catch (error) {
      toast.error(error instanceof ApiError ? error.message : "Restore failed")
    }
  }

  async function purge(entry: TrashEntry) {
    try {
      await purgeTrash(token, entry.id)
      toast.success(`Deleted ${entry.name} forever`)
      refresh()
    } catch (error) {
      toast.error(error instanceof ApiError ? error.message : "Delete failed")
    }
  }

  async function empty() {
    try {
      await emptyTrash(token)
      toast.success("Trash emptied")
      refresh()
    } catch (error) {
      toast.error(error instanceof ApiError ? error.message : "Could not empty the trash")
    }
  }

  if (entries.length === 0) {
    return (
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <Trash2Icon />
          </EmptyMedia>
          <EmptyTitle>Trash is empty</EmptyTitle>
          <EmptyDescription>
            Deleted files and folders wait here until restored or purged.
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    )
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex justify-end">
        <Button variant="outline" size="sm" onClick={empty}>
          <Trash2Icon />
          Empty trash
        </Button>
      </div>

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Name</TableHead>
            <TableHead>Original location</TableHead>
            <TableHead>Trashed</TableHead>
            <TableHead>Purges</TableHead>
            <TableHead />
          </TableRow>
        </TableHeader>
        <TableBody>
          {entries.map((entry) => (
            <TableRow key={entry.id}>
              <TableCell>
                <span className="flex items-center gap-2">
                  {entry.kind === "folder" ? (
                    <FolderIcon className="size-4 text-muted-foreground" />
                  ) : (
                    <FileIcon className="size-4 text-muted-foreground" />
                  )}
                  {entry.name}
                </span>
              </TableCell>
              <TableCell className="font-mono text-sm text-muted-foreground">
                {entry.trashed_from}
              </TableCell>
              <TableCell className="text-muted-foreground">
                {new Date(entry.trashed_at).toLocaleString()}
              </TableCell>
              <TableCell className="text-muted-foreground">
                {new Date(entry.purges_at).toLocaleDateString()}
              </TableCell>
              <TableCell className="text-right">
                <div className="flex justify-end gap-1">
                  <Button variant="ghost" size="sm" onClick={() => restore(entry)}>
                    <Undo2Icon />
                    Restore
                  </Button>
                  <Button variant="ghost" size="sm" onClick={() => purge(entry)}>
                    <XIcon />
                    Delete forever
                  </Button>
                </div>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}
