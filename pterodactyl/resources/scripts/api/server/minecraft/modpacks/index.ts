import http, { PaginationDataSet } from '@/api/http';
export interface Modpack {
    id: string;
    name: string;
    description: string;
    icon_url?: string;
}
export interface ModpackVersion {
    id: string;
    name: string;
}
interface ModpackResponse {
    object: string;
    data: Modpack[];
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
    data: ModpackVersion[];
}
interface InstallParams {
    provider: string;
    modpack_id: string;
    modpack_version_id: string;
    delete_server_files: boolean;
    name: string;
    icon_url?: string;
}
export interface RecentModpack {
    id: number;
    provider: string;
    modpack_id: string;
    name: string;
    version_id?: string;
    icon_url?: string;
    updated_at: string;
}
interface RecentResponse {
    object: string;
    data: RecentModpack[];
}
export const getModpacks = (
    uuid: string,
    params: { provider: string; page_size: number; page: number; search_query: string }
): Promise<ModpackResponse> => {
    return new Promise((resolve, reject) => {
        http.get(`/api/client/servers/${uuid}/modpacks`, { params })
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
export const getModpackVersions = (uuid: string, modpackId: string, provider: string): Promise<ModpackVersion[]> => {
    return new Promise((resolve, reject) => {
        http.get(`/api/client/servers/${uuid}/modpacks/${modpackId}/versions`, {
            params: { provider },
        })
            .then(({ data }) => resolve((data as VersionResponse).data || []))
            .catch(reject);
    });
};
export const getRecentModpacks = (uuid: string): Promise<RecentModpack[]> => {
    return new Promise((resolve, reject) => {
        http.get(`/api/client/servers/${uuid}/modpacks/recent`)
            .then(({ data }) => resolve((data as RecentResponse).data || []))
            .catch(reject);
    });
};
export const installModpack = (uuid: string, params: InstallParams): Promise<void> => {
    return new Promise((resolve, reject) => {
        http.post(`/api/client/servers/${uuid}/modpacks/install`, params)
            .then(() => resolve())
            .catch(reject);
    });
};
