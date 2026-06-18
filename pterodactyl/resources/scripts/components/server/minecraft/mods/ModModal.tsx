import React, { useEffect, useState } from 'react';
import { useHistory } from 'react-router-dom';
import { ServerContext } from '@/state/server';
import useFlash from '@/plugins/useFlash';
import { Dialog } from '@/components/elements/dialog';
import Select from '@/components/elements/Select';
import Label from '@/components/elements/Label';
import { getModVersions, installMod, ModVersion } from '@/api/server/minecraft/mods';
interface Props {
    mod: {
        id: string;
        name: string;
        description: string;
        icon_url?: string;
    } | null;
    provider: string;
    onDismissed: () => void;
    onInstalled: () => void;
}
export default ({ mod, provider, onDismissed, onInstalled }: Props) => {
    const uuid = ServerContext.useStoreState((state) => state.server.data!.uuid);
    const id = ServerContext.useStoreState((state) => state.server.data!.id);
    const history = useHistory();
    const { clearFlashes, clearAndAddHttpError, addFlash } = useFlash();
    const [versions, setVersions] = useState<ModVersion[]>([]);
    const [versionId, setVersionId] = useState('');
    const [loadingVersions, setLoadingVersions] = useState(false);
    useEffect(() => {
        if (!mod) return;
        setVersions([]);
        setVersionId('');
        setLoadingVersions(true);
        getModVersions(uuid, mod.id, provider)
            .then((data) => {
                setVersions(data);
                if (data.length > 0) {
                    setVersionId(data[0].id);
                }
            })
            .catch((error) => clearAndAddHttpError({ key: 'mods', error }))
            .finally(() => setLoadingVersions(false));
    }, [mod, provider, uuid]);
    const submit = () => {
        clearFlashes('mods');
        installMod(uuid, {
            provider,
            mod_id: mod?.id || '',
            version_id: versionId,
        })
            .then(() => {
                addFlash({
                    key: 'mods',
                    type: 'success',
                    message: `${mod?.name} Mod installation started successfully.`,
                });
                onInstalled();
            })
            .catch((error) => {
                clearAndAddHttpError({ key: 'mods', error });
            });
    };
    return (
        <Dialog.Confirm
            open={!!mod}
            onClose={onDismissed}
            title={`${mod?.name ?? ''}`}
            confirm={'Install Mod'}
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
