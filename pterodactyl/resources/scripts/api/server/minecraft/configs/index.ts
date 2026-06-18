import http from '@/api/http';
export interface ConfigFile {
    file: string;
    type: string;
    format: string;
    content: any | null;
    raw: string | null;
}
export interface ConfigsResponse {
    success: boolean;
    configs: ConfigFile[];
}
export const getConfigs = (uuid: string): Promise<ConfigsResponse> => {
    return http.get(`/api/client/servers/${uuid}/configs`)
        .then(response => response.data);
};
export const saveConfig = (uuid: string, file: string, contents: any | null, rawContent: string | null): Promise<void> => {
    return http.post(`/api/client/servers/${uuid}/configs/save`, {
        file,
        contents,
        raw_content: rawContent,
    })
        .then(response => response.data);
};
