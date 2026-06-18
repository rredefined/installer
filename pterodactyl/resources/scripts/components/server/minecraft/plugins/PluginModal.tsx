import React, { useEffect, useState } from 'react';
import { useHistory } from 'react-router-dom';
import { ServerContext } from '@/state/server';
import useFlash from '@/plugins/useFlash';
import { Dialog } from '@/components/elements/dialog';
import Select from '@/components/elements/Select';
import Label from '@/components/elements/Label';
import { getPluginVersions, installPlugin, PluginVersion } from '@/api/server/minecraft/plugins';
interface Props {
    plugin: {
        id: string;
        name: string;
        description: string;
        icon_url?: string;
    } | null;
    provider: string;
    onDismissed: () => void;
    onInstalled: () => void;
}
export default ({ plugin, provider, onDismissed, onInstalled }: Props) => {
    const uuid = ServerContext.useStoreState((state) => state.server.data!.uuid);
    const id = ServerContext.useStoreState((state) => state.server.data!.id);
    const history = useHistory();
    const { clearFlashes, clearAndAddHttpError, addFlash } = useFlash();
    const [versions, setVersions] = useState<PluginVersion[]>([]);
    const [versionId, setVersionId] = useState('');
    const [loadingVersions, setLoadingVersions] = useState(false);
    useEffect(() => {
        if (!plugin) return;
        setVersions([]);
        setVersionId('');
        setLoadingVersions(true);
        getPluginVersions(uuid, plugin.id, provider)
            .then((data) => {
                setVersions(data);
                if (data.length > 0) {
                    setVersionId(data[0].id);
                }
            })
            .catch((error) => clearAndAddHttpError({ key: 'plugins', error }))
            .finally(() => setLoadingVersions(false));
    }, [plugin, provider, uuid]);
    const submit = () => {
        clearFlashes('plugins');
        installPlugin(uuid, {
            provider,
            plugin_id: plugin?.id || '',
            version_id: versionId,
        })
            .then(() => {
                addFlash({
                    key: 'plugins',
                    type: 'success',
                    message: `${plugin?.name} Plugin installation started successfully.`,
                });
                onInstalled();
            })
            .catch((error) => {
                clearAndAddHttpError({ key: 'plugins', error });
            });
    };
    return (
        <Dialog.Confirm
            open={!!plugin}
            onClose={onDismissed}
            title={`${plugin?.name ?? ''}`}
            confirm={'Install Plugin'}
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
        </Dialog.Confirm>
    );
};
