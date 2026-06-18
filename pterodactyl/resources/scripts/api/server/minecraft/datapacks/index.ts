import http from '@/api/http';
export interface VTPack {
    name: string;
    display: string;
    description: string;
    support: string;
    incompatible: string[];
    video?: string;
    data?: any;
}
export interface VTCategory {
    category: string;
    packs: VTPack[];
    icon?: string;
}
export interface VTResponse {
    categories: VTCategory[];
}
export const getPacks = (uuid: string, version: string, type: string): Promise<VTResponse> => {
    return new Promise((resolve, reject) => {
        http.get(`/api/client/servers/${uuid}/datapacks`, { params: { version, type } })
            .then(({ data }) => resolve(data))
            .catch(reject);
    });
};
export const getVersions = (uuid: string): Promise<string[]> => {
    return new Promise((resolve, reject) => {
        http.get(`/api/client/servers/${uuid}/datapacks/versions`)
            .then(({ data }) => resolve(data))
            .catch(reject);
    });
};
export const detectVersion = (uuid: string): Promise<string | null> => {
    return new Promise((resolve, reject) => {
        http.get(`/api/client/servers/${uuid}/datapacks/detect-version`)
            .then(({ data }) => resolve(data.version))
            .catch(reject);
    });
};
export const getWorlds = (uuid: string): Promise<{ name: string }[]> => {
    return new Promise((resolve, reject) => {
        http.get(`/api/client/servers/${uuid}/datapacks/worlds`)
            .then(({ data }) => resolve(data))
            .catch(reject);
    });
};
export const installPacks = (
    uuid: string,
    params: { version: string; type: string; packs: any; world?: string }
): Promise<void> => {
    return new Promise((resolve, reject) => {
        http.post(`/api/client/servers/${uuid}/datapacks/install`, params)
            .then(() => resolve())
            .catch(reject);
    });
};
export const getPackImageUrl = (uuid: string, version: string, type: string, pack: string) => {
    return `/api/client/servers/${uuid}/datapacks/image?version=${version}&type=${type}&pack=${encodeURIComponent(
        pack
    )}`;
};
