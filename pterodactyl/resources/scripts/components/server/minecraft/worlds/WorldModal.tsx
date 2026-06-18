import React, { useEffect, useState } from 'react';
import { useHistory } from 'react-router-dom';
import { ServerContext } from '@/state/server';
import useFlash from '@/plugins/useFlash';
import { Dialog } from '@/components/elements/dialog';
import { Button } from '@/components/elements/button';
import Select from '@/components/elements/Select';
import Label from '@/components/elements/Label';
import {
    getWorldVersions,
    installWorld,
    getWorldDownloadStatus,
    queryWorldFile,
    WorldVersion,
} from '@/api/server/minecraft/worlds';
import loadDirectory from '@/api/server/files/loadDirectory';
import { cleanDirectoryPath } from '@/helpers';
import { bytesToString } from '@/lib/formatters';
interface Props {
    world: {
        id: string;
        name: string;
        description: string;
        icon_url?: string;
    } | null;
    provider: string;
    onDismissed: () => void;
    onInstalled: () => void;
}
export default ({ world, provider, onDismissed, onInstalled }: Props) => {
    const uuid = ServerContext.useStoreState((state) => state.server.data!.uuid);
    const id = ServerContext.useStoreState((state) => state.server.data!.id);
    const history = useHistory();
    const { clearFlashes, clearAndAddHttpError, addFlash } = useFlash();
    const [versions, setVersions] = useState<WorldVersion[]>([]);
    const [versionId, setVersionId] = useState('');
    const [loadingVersions, setLoadingVersions] = useState(false);
    const [isInstalling, setIsInstalling] = useState(false);
    const [downloadId, setDownloadId] = useState<string | null>(null);
    const [downloadStatus, setDownloadStatus] = useState<'downloading' | 'completed' | 'not_found'>('downloading');
    const [progress, setProgress] = useState(0);
    const [fileInfo, setFileInfo] = useState<{ filename: string; size: number } | null>(null);
    const [loadingFileInfo, setLoadingFileInfo] = useState(false);
    const [pullInterval, setPullInterval] = useState<NodeJS.Timeout>();
    const [ranInterval, setRanInterval] = useState(false);
    const [rootFiles, setRootFiles] = useState<any[]>([]);
    useEffect(() => {
        if (!world) return;
        setVersions([]);
        setVersionId('');
        setLoadingVersions(true);
        getWorldVersions(uuid, world.id, provider)
            .then((data) => {
                setVersions(data);
                if (data.length > 0) {
                    setVersionId(data[0].id);
                }
            })
            .catch((error) => clearAndAddHttpError({ key: 'worlds', error }))
            .finally(() => setLoadingVersions(false));
    }, [world, provider, uuid]);
    useEffect(() => {
        if (!versionId || !world) return;
        setLoadingFileInfo(true);
        setFileInfo(null);
        queryWorldFile(uuid, {
            provider,
            world_id: world.id,
            version_id: versionId,
        })
            .then((data) => {
                setFileInfo({
                    filename: data.filename,
                    size: data.size || 0,
                });
            })
            .catch((error) => {
                clearAndAddHttpError({ key: 'worlds', error });
            })
            .finally(() => setLoadingFileInfo(false));
    }, [versionId, world, uuid, provider, clearAndAddHttpError]);
    useEffect(() => {
        if (!isInstalling && pullInterval) {
            clearInterval(pullInterval);
            setPullInterval(undefined);
        }
    }, [isInstalling, pullInterval]);
    useEffect(() => {
        if (!world) {
            if (pullInterval) clearInterval(pullInterval);
            setIsInstalling(false);
            setProgress(0);
            setFileInfo(null);
            setRootFiles([]);
            setRanInterval(false);
            setDownloadId(null);
            setDownloadStatus('downloading');
        }
    }, [world, pullInterval]);
    useEffect(() => {
        if (!isInstalling || !fileInfo) return;
        loadDirectory(uuid, '/').then((files) => {
            const fileObj = files.find((f) => f.name === fileInfo.filename);
            setRootFiles(files);
            const progressPercent = ((fileObj?.size ?? 0) / fileInfo.size) * 100;
            setProgress(Math.min(progressPercent, 99));
        });
    }, [isInstalling, fileInfo, uuid]);
    useEffect(() => {
        if (!isInstalling || !fileInfo) return;
        const fileObj = rootFiles?.find((f) => f.name === fileInfo.filename);
        if ((fileObj && fileObj.size === fileInfo.size) || (!fileObj && ranInterval)) {
            clearFlashes('worlds');
            setIsInstalling(false);
            setProgress(100);
            setDownloadStatus('completed');
            addFlash({
                key: 'worlds',
                type: 'success',
                message: `${world?.name} World downloaded successfully!`,
            });
            onDismissed();
            onInstalled();
        }
    }, [isInstalling, rootFiles, fileInfo, ranInterval, world, onDismissed, onInstalled, addFlash, clearFlashes]);
    const submit = () => {
        clearFlashes('worlds');
        setIsInstalling(true);
        setProgress(0);
        setRanInterval(false);
        setPullInterval(
            setInterval(() => {
                loadDirectory(uuid, '/').then((files) => {
                    setRootFiles(files);
                    setRanInterval(true);
                });
            }, 2000)
        );
        installWorld(uuid, {
            provider,
            world_id: world?.id || '',
            version_id: versionId,
        })
            .then((data) => {
                setDownloadId(data.download_id);
                setDownloadStatus('downloading');
            })
            .catch((error) => {
                setIsInstalling(false);
                if (pullInterval) clearInterval(pullInterval);
                clearAndAddHttpError({ key: 'worlds', error });
            });
    };
    return (
        <Dialog open={!!world} onClose={() => !isInstalling && onDismissed()} title={`${world?.name ?? ''}`}>
            <form
                id={'world-install-form'}
                onSubmit={(e) => {
                    e.preventDefault();
                    if (isInstalling || !fileInfo) return;
                    submit();
                }}
            >
                <div className={'mb-4'}>
                    <Label>Select Version</Label>
                    <Select
                        name={'versionId'}
                        value={versionId}
                        onChange={(e) => setVersionId(e.target.value)}
                        disabled={loadingVersions || versions.length === 0 || isInstalling}
                    >
                        {loadingVersions && <option>Loading versions...</option>}
                        {!loadingVersions && versions.length === 0 && <option>No versions found</option>}
                        {versions.map((v) => (
                            <option key={v.id} value={v.id}>
                                {v.name}
                            </option>
                        ))}
                    </Select>
                </div>
            </form>
            <Dialog.Footer>
                <Button.Text onClick={() => !isInstalling && onDismissed()}>Cancel</Button.Text>
                <Button type={'submit'} form={'world-install-form'} disabled={!fileInfo || isInstalling}>
                    {fileInfo ? (
                        <>
                            Install World {fileInfo?.size ? bytesToString(fileInfo.size) : ''}{' '}
                            {isInstalling
                                ? `(${(
                                      ((rootFiles?.find((f) => f.name === fileInfo.filename)?.size ?? 0) /
                                          fileInfo.size) *
                                      100
                                  ).toFixed(2)}%)`
                                : ''}
                        </>
                    ) : (
                        'Install World'
                    )}
                </Button>
            </Dialog.Footer>
        </Dialog>
    );
};
