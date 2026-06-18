import React, { useEffect, useState } from 'react';
import { useHistory } from 'react-router-dom';
import { ServerContext } from '@/state/server';
import useFlash from '@/plugins/useFlash';
import { Dialog } from '@/components/elements/dialog';
import Select from '@/components/elements/Select';
import Switch from '@/components/elements/Switch';
import Label from '@/components/elements/Label';
import { getModpackVersions, installModpack, ModpackVersion } from '@/api/server/minecraft/modpacks';
interface Props {
    modpack: {
        id: string;
        name: string;
        description: string;
        icon_url?: string;
    } | null;
    provider: string;
    onDismissed: () => void;
    onInstalled: () => void;
}
export default ({ modpack, provider, onDismissed, onInstalled }: Props) => {
    const uuid = ServerContext.useStoreState((state) => state.server.data!.uuid);
    const id = ServerContext.useStoreState((state) => state.server.data!.id);
    const history = useHistory();
    const { clearFlashes, clearAndAddHttpError, addFlash } = useFlash();
    const [versions, setVersions] = useState<ModpackVersion[]>([]);
    const [versionId, setVersionId] = useState('');
    const [deleteFiles, setDeleteFiles] = useState(false);
    const [loadingVersions, setLoadingVersions] = useState(false);
    useEffect(() => {
        if (!modpack) return;
        setVersions([]);
        setVersionId('');
        setDeleteFiles(false);
        setLoadingVersions(true);
        getModpackVersions(uuid, modpack.id, provider)
            .then((data) => {
                setVersions(data);
                if (data.length > 0) {
                    setVersionId(data[0].id);
                }
            })
            .catch((error) => clearAndAddHttpError({ key: 'modpacks', error }))
            .finally(() => setLoadingVersions(false));
    }, [modpack, provider, uuid]);
    const submit = () => {
        clearFlashes('modpacks');
        installModpack(uuid, {
            provider,
            modpack_id: modpack?.id || '',
            modpack_version_id: versionId,
            delete_server_files: deleteFiles,
            name: modpack?.name || '',
            icon_url: modpack?.icon_url,
        })
            .then(() => {
                addFlash({
                    key: 'modpacks',
                    type: 'success',
                    message: `${modpack?.name} Modpack installation started successfully.`,
                });
                onInstalled();
                setTimeout(() => {
                    history.push(`/server/${id}`);
                }, 1000);
            })
            .catch((error) => {
                clearAndAddHttpError({ key: 'modpacks', error });
            });
    };
    return (
        <Dialog.Confirm
            open={!!modpack}
            onClose={onDismissed}
            title={`${modpack?.name ?? ''}`}
            confirm={'Install Modpack'}
            onConfirmed={submit}
        >
            <div className={'mb-4'}>
                <Label>Select Version</Label>
                <Select
                    name={'versionId'}
                    value={versionId}
                    onChange={(e) => setVersionId(e.target.value)}
                    disabled={loadingVersions || versions.length === 0}
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
            <div className={'bg-neutral-700 p-4 rounded border border-neutral-600'}>
                <Switch
                    name={'deleteFiles'}
                    label={'Delete Existing Files'}
                    description={'This will delete all files in your server before installing.'}
                    defaultChecked={deleteFiles}
                    onChange={() => setDeleteFiles(!deleteFiles)}
                />
            </div>
        </Dialog.Confirm>
    );
};
