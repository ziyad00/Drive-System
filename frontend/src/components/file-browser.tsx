import { useCallback, useEffect, useRef, useState } from "react"
import { toast } from "sonner"
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
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
import { NameDialog } from "@/components/name-dialog"
import { VersionsDialog } from "@/components/versions-dialog"
import {
  ApiError,
  createFile,
  createFolder,
  downloadFile,
  getPath,
  renameNode,
  replaceFile,
  trashNode,
  type TreeNode,
} from "@/lib/api"
import { fileToBase64, formatBytes } from "@/lib/blob-utils"
import {
  DownloadIcon,
  FileIcon,
  FolderIcon,
  FolderPlusIcon,
  HistoryIcon,
  MoreVerticalIcon,
  PencilIcon,
  Trash2Icon,
  UploadIcon,
} from "lucide-react"

export function FileBrowser({ token, refreshSignal }: { token: string; refreshSignal: number }) {
  const [path, setPath] = useState("/")
  const [folder, setFolder] = useState<TreeNode | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [creatingFolder, setCreatingFolder] = useState(false)
  const [renaming, setRenaming] = useState<TreeNode | null>(null)
  const [versionsOf, setVersionsOf] = useState<TreeNode | null>(null)
  const fileInput = useRef<HTMLInputElement>(null)

  const refresh = useCallback(async () => {
    try {
      setFolder(await getPath(token, path))
      setError(null)
    } catch (err) {
      if (err instanceof ApiError && err.status === 404 && path !== "/") {
        setPath("/")
        return
      }
      setFolder(null)
      setError(err instanceof ApiError ? err.message : "Something went wrong.")
    }
  }, [token, path])

  useEffect(() => {
    refresh()
  }, [refresh, refreshSignal])

  const joinPath = (name: string) => (path === "/" ? `/${name}` : `${path}/${name}`)

  async function uploadPicked(file: File) {
    const target = joinPath(file.name)
    const data = await fileToBase64(file)
    try {
      await createFile(token, target, data, file.type || undefined)
      toast.success(`Uploaded ${file.name}`)
      refresh()
    } catch (error) {
      if (error instanceof ApiError && error.status === 409) {
        toast(`${file.name} already exists`, {
          description: "Replace it? The current content is kept as a version.",
          action: {
            label: "Replace",
            onClick: async () => {
              try {
                await replaceFile(token, target, data, file.type || undefined)
                toast.success(`Replaced ${file.name}`)
                refresh()
              } catch (err) {
                toast.error(err instanceof ApiError ? err.message : "Replace failed")
              }
            },
          },
        })
      } else {
        toast.error(error instanceof ApiError ? error.message : "Upload failed")
      }
    }
  }

  async function makeFolder(name: string) {
    try {
      await createFolder(token, joinPath(name))
      refresh()
    } catch (error) {
      toast.error(error instanceof ApiError ? error.message : "Could not create folder")
    }
  }

  async function rename(node: TreeNode, name: string) {
    try {
      await renameNode(token, node.id, name)
      refresh()
    } catch (error) {
      toast.error(error instanceof ApiError ? error.message : "Rename failed")
    }
  }

  async function moveToTrash(node: TreeNode) {
    try {
      await trashNode(token, node.id)
      toast.success(`Moved ${node.name} to the trash`)
      refresh()
    } catch (error) {
      toast.error(error instanceof ApiError ? error.message : "Delete failed")
    }
  }

  async function download(node: TreeNode) {
    try {
      const blob = await downloadFile(token, node.path)
      const url = URL.createObjectURL(blob)
      const anchor = document.createElement("a")
      anchor.href = url
      anchor.download = node.name
      anchor.click()
      URL.revokeObjectURL(url)
    } catch (error) {
      toast.error(error instanceof ApiError ? error.message : "Download failed")
    }
  }

  const crumbs = path.split("/").filter(Boolean)

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <Breadcrumb>
          <BreadcrumbList>
            <BreadcrumbItem>
              {crumbs.length === 0 ? (
                <BreadcrumbPage className="font-mono">/</BreadcrumbPage>
              ) : (
                <BreadcrumbLink className="cursor-pointer font-mono" onClick={() => setPath("/")}>
                  /
                </BreadcrumbLink>
              )}
            </BreadcrumbItem>
            {crumbs.map((segment, index) => (
              <BreadcrumbItem key={index}>
                {index > 0 && <BreadcrumbSeparator />}
                {index === crumbs.length - 1 ? (
                  <BreadcrumbPage className="font-mono">{segment}</BreadcrumbPage>
                ) : (
                  <BreadcrumbLink
                    className="cursor-pointer font-mono"
                    onClick={() => setPath("/" + crumbs.slice(0, index + 1).join("/"))}
                  >
                    {segment}
                  </BreadcrumbLink>
                )}
              </BreadcrumbItem>
            ))}
          </BreadcrumbList>
        </Breadcrumb>

        <div className="flex gap-2">
          <Button variant="outline" size="sm" onClick={() => setCreatingFolder(true)}>
            <FolderPlusIcon />
            New folder
          </Button>
          <Button size="sm" onClick={() => fileInput.current?.click()}>
            <UploadIcon />
            Upload
          </Button>
          <input
            ref={fileInput}
            type="file"
            className="hidden"
            onChange={(e) => {
              const picked = e.target.files?.[0]
              if (picked) uploadPicked(picked)
              e.target.value = ""
            }}
          />
        </div>
      </div>

      {error && (
        <div className="rounded-md border border-destructive/30 bg-destructive/5 px-4 py-3 text-sm text-destructive">
          {error}
        </div>
      )}

      {folder && folder.children?.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <FolderIcon />
            </EmptyMedia>
            <EmptyTitle>Empty folder</EmptyTitle>
            <EmptyDescription>Upload a file or create a folder to get started.</EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : folder ? (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Size</TableHead>
              <TableHead>Type</TableHead>
              <TableHead>Backend</TableHead>
              <TableHead>Modified</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {folder.children?.map((node) => (
              <TableRow key={node.id}>
                <TableCell>
                  {node.kind === "folder" ? (
                    <button
                      type="button"
                      className="flex items-center gap-2 font-medium hover:underline"
                      onClick={() => setPath(node.path)}
                    >
                      <FolderIcon className="size-4 text-muted-foreground" />
                      {node.name}
                    </button>
                  ) : (
                    <span className="flex items-center gap-2">
                      <FileIcon className="size-4 text-muted-foreground" />
                      {node.name}
                    </span>
                  )}
                </TableCell>
                <TableCell>{node.size ? formatBytes(Number(node.size)) : "—"}</TableCell>
                <TableCell className="max-w-40 truncate text-muted-foreground">
                  {node.kind === "folder" ? "folder" : node.content_type || "—"}
                </TableCell>
                <TableCell>
                  {node.backend ? (
                    <Badge variant="secondary" className="font-mono">
                      {node.backend}
                    </Badge>
                  ) : (
                    "—"
                  )}
                </TableCell>
                <TableCell className="text-muted-foreground">
                  {new Date(node.updated_at).toLocaleString()}
                </TableCell>
                <TableCell className="text-right">
                  <DropdownMenu>
                    <DropdownMenuTrigger
                      render={
                        <Button variant="ghost" size="sm" aria-label={`Actions for ${node.name}`} />
                      }
                    >
                      <MoreVerticalIcon />
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      {node.kind === "file" && (
                        <DropdownMenuItem onClick={() => download(node)}>
                          <DownloadIcon />
                          Download
                        </DropdownMenuItem>
                      )}
                      {node.kind === "file" && (
                        <DropdownMenuItem onClick={() => setVersionsOf(node)}>
                          <HistoryIcon />
                          Versions
                        </DropdownMenuItem>
                      )}
                      <DropdownMenuItem onClick={() => setRenaming(node)}>
                        <PencilIcon />
                        Rename
                      </DropdownMenuItem>
                      <DropdownMenuItem variant="destructive" onClick={() => moveToTrash(node)}>
                        <Trash2Icon />
                        Move to trash
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      ) : null}

      <NameDialog
        open={creatingFolder}
        title="New folder"
        action="Create"
        onSubmit={makeFolder}
        onClose={() => setCreatingFolder(false)}
      />
      <NameDialog
        open={!!renaming}
        title={`Rename ${renaming?.name ?? ""}`}
        action="Rename"
        initial={renaming?.name ?? ""}
        onSubmit={(name) => renaming && rename(renaming, name)}
        onClose={() => setRenaming(null)}
      />
      <VersionsDialog
        token={token}
        node={versionsOf}
        onClose={() => setVersionsOf(null)}
        onRestored={refresh}
      />
    </div>
  )
}
