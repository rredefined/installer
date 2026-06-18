import http from '@/api/http';
export interface Mod {
    id: string;
    name: string;
    description: string;
    icon_url?: string;
}
export interface ModVersion {
    id: string;
    name: string;
}
interface ModResponse {
    object: string;
    data: Mod[];
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
    data: ModVersion[];
}
interface InstallParams {
    provider: string;
    mod_id: string;
    version_id: string;
}
export const getMods = (
    uuid: string,
    params: {
        provider: string;
        page_size: number;
        page: number;
        search_query: string;
        minecraft_version?: string;
        loader?: string;
    }
): Promise<ModResponse> => {
    return new Promise((resolve, reject) => {
        http.get(`/api/client/servers/${uuid}/mods`, { params })
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
export const getModVersions = (uuid: string, modId: string, provider: string): Promise<ModVersion[]> => {
    return new Promise((resolve, reject) => {
        http.get(`/api/client/servers/${uuid}/mods/${modId}/versions`, {
            params: { provider },
        })
            .then(({ data }) => resolve((data as VersionResponse).data || []))
            .catch(reject);
    });
};
export const installMod = (uuid: string, params: InstallParams): Promise<void> => {
    return new Promise((resolve, reject) => {
        http.post(`/api/client/servers/${uuid}/mods/install`, params)
            .then(() => resolve())
            .catch(reject);
    });
};
