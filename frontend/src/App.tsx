import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { FileBrowser } from "@/components/file-browser"
import { TrashView } from "@/components/trash-view"
import { useTheme } from "@/lib/theme"
import { DatabaseIcon, ExternalLinkIcon, MoonIcon, SunIcon } from "lucide-react"

const MINIO_CONSOLE = import.meta.env.VITE_MINIO_CONSOLE ?? "http://localhost:9001"

export default function App() {
  // The dev-token convenience default never ships in production builds.
  const [token, setToken] = useState(
    () => localStorage.getItem("simple-drive-token") ?? (import.meta.env.DEV ? "dev-token" : "")
  )
  const [refreshSignal, setRefreshSignal] = useState(0)
  const { theme, toggle } = useTheme()

  function updateToken(next: string) {
    setToken(next)
    localStorage.setItem("simple-drive-token", next)
  }

  const bump = () => setRefreshSignal((n) => n + 1)

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
              onChange={(e) => updateToken(e.target.value)}
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

      <Tabs defaultValue="files" onValueChange={bump}>
        <TabsList>
          <TabsTrigger value="files">Files</TabsTrigger>
          <TabsTrigger value="trash">Trash</TabsTrigger>
        </TabsList>
        <TabsContent value="files" className="pt-4">
          <FileBrowser token={token} refreshSignal={refreshSignal} />
        </TabsContent>
        <TabsContent value="trash" className="pt-4">
          <TrashView token={token} refreshSignal={refreshSignal} onRestored={bump} />
        </TabsContent>
      </Tabs>
    </div>
  )
}
