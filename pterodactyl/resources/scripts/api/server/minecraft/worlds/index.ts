import http, { PaginationDataSet } from '@/api/http';
export interface World {
    id: string;
    name: string;
    description: string;
    icon_url?: string;
}
export interface WorldVersion {
    id: string;
    name: string;
}
interface WorldResponse {
    object: string;
    data: World[];
    meta: {
        pagination: {
            total: number;
            count: number;
            per_page: number;
            current_page: number;
            total_pages: number;
        };
    };
}
interface VersionResponse {
    object: string;
    data: WorldVersion[];
}
interface InstallParams {
    provider: string;
    world_id: string;
    version_id: string;
}
export interface InstalledWorld {
    name: string;
    is_active?: boolean;
}
interface InstalledResponse {
    object: string;
    data: InstalledWorld[];
    meta: {
        active_world: string;
    };
}
export const getWorlds = (
    uuid: string,
    params: { provider: string; page_size: number; page: number; search_query: string }
): Promise<WorldResponse> => {
    return new Promise((resolve, reject) => {
        http.get(`/api/client/servers/${uuid}/worlds`, { params })
            .then(({ data }) => {
                resolve(
                    data || {
                        data: [],
                        meta: { pagination: { total: 0, count: 0, per_page: 10, current_page: 1, total_pages: 1 } },
                    }
                );
            })
            .catch(reject);
    });
};
export const getWorldVersions = (uuid: string, worldId: string, provider: string): Promise<WorldVersion[]> => {
    return new Promise((resolve, reject) => {
        http.get(`/api/client/servers/${uuid}/worlds/${worldId}/versions`, {
            params: { provider },
        })
            .then(({ data }) => resolve((data as VersionResponse).data || []))
            .catch(reject);
    });
};
export const getInstalledWorlds = (uuid: string): Promise<{ worlds: InstalledWorld[]; active_world: string }> => {
    return new Promise((resolve, reject) => {
        http.get(`/api/client/servers/${uuid}/worlds/installed`)
            .then(({ data }) => {
                const response = data as InstalledResponse;
                resolve({
                    worlds: response.data,
                    active_world: response.meta.active_world,
                });
            })
            .catch(reject);
    });
};
export const deleteWorld = (uuid: string, name: string): Promise<void> => {
    return new Promise((resolve, reject) => {
        http.post(`/api/client/servers/${uuid}/worlds/delete`, { name })
            .then(() => resolve())
            .catch(reject);
    });
};
export const setActiveWorld = (uuid: string, name: string): Promise<void> => {
    return new Promise((resolve, reject) => {
        http.post(`/api/client/servers/${uuid}/worlds/set-active`, { name })
            .then(() => resolve())
            .catch(reject);
    });
};
export const installWorld = (uuid: string, params: InstallParams): Promise<{ download_id: string; message: string }> => {
    return new Promise((resolve, reject) => {
        http.post(`/api/client/servers/${uuid}/worlds/install`, params)
            .then(({ data }) => resolve(data))
            .catch(reject);
    });
};
export const getWorldDownloadStatus = (uuid: string, downloadId: string): Promise<{
    status: 'downloading' | 'completed' | 'not_found';
    filename?: string;
    download_id?: string;
    message?: string;
}> => {
    return new Promise((resolve, reject) => {
        http.get(`/api/client/servers/${uuid}/worlds/download-status/${downloadId}`)
            .then(({ data }) => resolve(data))
            .catch(reject);
    });
};
export const queryWorldFile = (uuid: string, params: {
    provider: string;
    world_id: string;
    version_id: string;
}): Promise<{ filename: string; size: number | null }> => {
    return new Promise((resolve, reject) => {
        http.post(`/api/client/servers/${uuid}/worlds/query`, params)
            .then(({ data }) => resolve(data))
            .catch(reject);
    });
};
