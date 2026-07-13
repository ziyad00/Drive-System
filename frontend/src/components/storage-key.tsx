import { useEffect, useState } from "react"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { storageKey } from "@/lib/blob-utils"
import { toast } from "sonner"

// Every object is stored under SHA-256(id). This renders that key as a color
// band (first 12 bytes -> 12 hue slices) plus a short hex prefix, so a row in
// this table can be matched by eye to the object folder in the MinIO browser.
export function StorageKey({ id }: { id: string }) {
  const [key, setKey] = useState<string | null>(null)

  useEffect(() => {
    let alive = true
    storageKey(id).then((k) => {
      if (alive) setKey(k)
    })
    return () => {
      alive = false
    }
  }, [id])

  if (!key) return <div className="h-5 w-[7.5rem]" />

  const bytes = Array.from({ length: 12 }, (_, i) => parseInt(key.slice(i * 2, i * 2 + 2), 16))

  return (
    <Tooltip>
      <TooltipTrigger
        render={
          <button
            type="button"
            className="group flex items-center gap-2"
            onClick={() => {
              navigator.clipboard.writeText(key)
              toast.success("Storage key copied")
            }}
          />
        }
      >
        <span className="flex h-4 w-16 overflow-hidden rounded-xs">
          {bytes.map((b, i) => (
            <span
              key={i}
              className="h-full flex-1"
              style={{ backgroundColor: `hsl(${(b / 255) * 360} 60% ${38 + (b % 4) * 7}%)` }}
            />
          ))}
        </span>
        <code className="font-mono text-xs text-muted-foreground group-hover:text-foreground">
          {key.slice(0, 12)}
        </code>
      </TooltipTrigger>
      <TooltipContent side="right" className="max-w-[26rem]">
        <p className="font-mono text-xs break-all">{key}</p>
        <p className="mt-1 text-xs text-muted-foreground">
          SHA-256 of the id — the object's name in the storage backend. Click to copy.
        </p>
      </TooltipContent>
    </Tooltip>
  )
}
