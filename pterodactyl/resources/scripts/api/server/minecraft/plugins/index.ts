import http from '@/api/http';
export interface Plugin {
    id: string;
    name: string;
    description: string;
    icon_url?: string;
}
export interface PluginVersion {
    id: string;
    name: string;
}
interface PluginResponse {
    object: string;
    data: Plugin[];
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
    data: PluginVersion[];
}
interface InstallParams {
    provider: string;
    plugin_id: string;
    version_id: string;
}
export const getPlugins = (
    uuid: string,
    params: {
        provider: string;
        page_size: number;
        page: number;
        search_query: string;
        minecraft_version?: string;
        loader?: string;
    }
): Promise<PluginResponse> => {
    return new Promise((resolve, reject) => {
        http.get(`/api/client/servers/${uuid}/plugins`, { params })
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
export const getPluginVersions = (uuid: string, pluginId: string, provider: string): Promise<PluginVersion[]> => {
    return new Promise((resolve, reject) => {
        http.get(`/api/client/servers/${uuid}/plugins/${pluginId}/versions`, {
            params: { provider },
        })
            .then(({ data }) => resolve((data as VersionResponse).data || []))
            .catch(reject);
    });
};
export const installPlugin = (uuid: string, params: InstallParams): Promise<void> => {
    return new Promise((resolve, reject) => {
        http.post(`/api/client/servers/${uuid}/plugins/install`, params)
            .then(() => resolve())
            .catch(reject);
    });
};
