import http from '@/api/http';
export interface ForkInfo {
    icon?: string;
    builds?: number | string;
    versions?: {
        minecraft?: number | string;
        project?: number;
    };
    name: string;
    color?: string;
    homepage?: string;
    deprecated?: boolean;
    experimental?: boolean;
    description?: string;
    categories?: string[];
    compatibility?: string[];
}
export interface MinecraftForkResponse {
    success: boolean;
    forks: Record<string, ForkInfo>;
}
export interface BuildInfo {
    id?: number;
    type?: string;
    projectVersionId?: string | null;
    versionId?: string | null;
    buildNumber: number | string;
    name: string;
    experimental?: boolean;
    created?: string | null;
    time?: string;
    channel?: string;
    jarUrl?: string | null;
    jarSize?: number | null;
    jarLocation?: string | null;
    zipUrl?: string | null;
    zipSize?: number | null;
    changes?: string[];
}
export interface VersionInfo {
    type: 'RELEASE' | 'SNAPSHOT' | string;
    supported: boolean;
    java?: number;
    created?: string;
    builds: number | string;
    latest?: BuildInfo;
}
export interface MinecraftVersionResponse {
    success: boolean;
    versions: Record<string, VersionInfo>;
}
export interface MinecraftBuildsResponse {
    success: boolean;
    builds: BuildInfo[];
}
export interface UpdateMinecraftVersionRequest {
    type: string;
    version: string;
    build: string;
    buildName?: string;
    deleteFiles?: boolean;
    acceptEula?: boolean;
}
export interface CurrentMinecraftVersionResponse {
    success: boolean;
    warning?: boolean;
    message?: string;
    current: {
        type: string;
        version: string;
        build: string;
    };
}
export const getMinecraftForks = (uuid: string): Promise<MinecraftForkResponse> => {
    return http.get(`/api/client/servers/${uuid}/versions/forks`)
        .then(response => response.data);
};
export const getVersions = (uuid: string, type: string): Promise<MinecraftVersionResponse> => {
    return http.get(`/api/client/servers/${uuid}/versions/versions/${type}`)
        .then(response => response.data);
};
export const getBuilds = (uuid: string, type: string, version: string): Promise<MinecraftBuildsResponse> => {
    return http.get(`/api/client/servers/${uuid}/versions/builds/${type}/${version}`)
        .then(response => response.data);
};
export const updateMinecraftVersion = (uuid: string, data: UpdateMinecraftVersionRequest): Promise<any> => {
    return http.post(`/api/client/servers/${uuid}/versions/install`, data)
        .then(response => response.data);
};
export const getCurrentVersion = (uuid: string): Promise<CurrentMinecraftVersionResponse> => {
    return http.get(`/api/client/servers/${uuid}/versions/current`)
        .then(response => response.data);
};
