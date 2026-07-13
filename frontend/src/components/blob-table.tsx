import { useState } from "react"
import { toast } from "sonner"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
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
import { StorageKey } from "@/components/storage-key"
import { ApiError, getBlob, type BlobMeta } from "@/lib/api"
import { downloadBase64, formatBytes } from "@/lib/blob-utils"
import { ArchiveIcon, DownloadIcon } from "lucide-react"

export function BlobTable({ token, blobs }: { token: string; blobs: BlobMeta[] }) {
  const [downloading, setDownloading] = useState<string | null>(null)

  async function download(id: string) {
    setDownloading(id)
    try {
      const blob = await getBlob(token, id)
      downloadBase64(blob.id, blob.data)
    } catch (error) {
      const message = error instanceof ApiError ? error.message : "Download failed"
      toast.error(message)
    } finally {
      setDownloading(null)
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Stored blobs</CardTitle>
        <CardDescription>
          {blobs.length === 0
            ? "Metadata from the tracking table; content lives in the storage backend."
            : `${blobs.length} object${blobs.length === 1 ? "" : "s"} tracked. The color band is the SHA-256 storage key — match it to the folder name in MinIO.`}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {blobs.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ArchiveIcon />
              </EmptyMedia>
              <EmptyTitle>Nothing stored yet</EmptyTitle>
              <EmptyDescription>
                Store a file on the left — it will appear here, and in the MinIO object browser
                under its storage key.
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Id</TableHead>
                <TableHead>Storage key</TableHead>
                <TableHead>Size</TableHead>
                <TableHead>Backend</TableHead>
                <TableHead>Created</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {blobs.map((blob) => (
                <TableRow key={blob.id}>
                  <TableCell className="max-w-56 truncate font-mono text-sm" title={blob.id}>
                    {blob.id}
                  </TableCell>
                  <TableCell>
                    <StorageKey id={blob.id} />
                  </TableCell>
                  <TableCell title={`${blob.size} bytes`}>
                    {formatBytes(Number(blob.size))}
                  </TableCell>
                  <TableCell>
                    <Badge variant="secondary" className="font-mono">
                      {blob.backend}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {new Date(blob.created_at).toLocaleString()}
                  </TableCell>
                  <TableCell className="text-right">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => download(blob.id)}
                      disabled={downloading === blob.id}
                    >
                      <DownloadIcon />
                      {downloading === blob.id ? "Fetching…" : "Download"}
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}
