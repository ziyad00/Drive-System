export interface BlobMeta {
  id: string
  size: string
  backend: string
  created_at: string
}

export interface BlobRecord extends BlobMeta {
  data: string
}

const BASE = import.meta.env.VITE_API_URL ?? "http://localhost:3000"

export class ApiError extends Error {
  status: number

  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

async function request<T>(path: string, token: string, init?: RequestInit): Promise<T> {
  let res: Response
  try {
    res = await fetch(`${BASE}${path}`, {
      ...init,
      headers: {
        Authorization: `Bearer ${token}`,
        ...(init?.body ? { "Content-Type": "application/json" } : {}),
      },
    })
  } catch {
    throw new ApiError(0, `API unreachable at ${BASE} — is the Rails server running?`)
  }

  const body = await res.json().catch(() => null)
  if (!res.ok) {
    throw new ApiError(res.status, body?.error ?? `request failed (${res.status})`)
  }
  return body as T
}

export function listBlobs(token: string): Promise<BlobMeta[]> {
  return request("/v1/blobs", token)
}

export function getBlob(token: string, id: string): Promise<BlobRecord> {
  return request(`/v1/blobs/${encodeURIComponent(id)}`, token)
}

export function storeBlob(
  token: string,
  id: string,
  data: string,
  backend?: string
): Promise<BlobRecord> {
  return request("/v1/blobs", token, {
    method: "POST",
    body: JSON.stringify(backend ? { id, data, backend } : { id, data }),
  })
}

export interface BackendInfo {
  available: string[]
  default: string
  user_default: string | null
  system_default: string
}

export function getBackends(token: string): Promise<BackendInfo> {
  return request("/v1/backends", token)
}

export function setDefaultBackend(token: string, backend: string | null): Promise<BackendInfo> {
  return request("/v1/backends/default", token, {
    method: "PUT",
    body: JSON.stringify({ backend }),
  })
}
