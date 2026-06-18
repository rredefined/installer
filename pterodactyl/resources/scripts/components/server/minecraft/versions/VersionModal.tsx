import React, { useEffect, useState } from 'react';
import { ServerContext } from '@/state/server';
import { BuildInfo, getBuilds, updateMinecraftVersion } from '@/api/server/minecraft/versions';
import FlashMessageRender from '@/components/FlashMessageRender';
import { httpErrorToHuman } from '@/api/http';
import useFlash from '@/plugins/useFlash';
import Select from '@/components/elements/Select';
import { Dialog } from '@/components/elements/dialog';
import Switch from '@/components/elements/Switch';
import Label from '@/components/elements/Label';
interface Props {
    version: string | null;
    fork: string;
    onDismissed: () => void;
    onInstalled: () => void;
}
export default ({ version, fork, onDismissed, onInstalled }: Props) => {
    const { addError, clearFlashes, addFlash } = useFlash();
    const uuid = ServerContext.useStoreState((state) => state.server.data!.uuid);
    const [builds, setBuilds] = useState<BuildInfo[]>([]);
    const [loading, setLoading] = useState(false);
    const [selectedBuild, setSelectedBuild] = useState<string>('');
    const [deleteFiles, setDeleteFiles] = useState(false);
    const [acceptEula, setAcceptEula] = useState(false);
    useEffect(() => {
        if (!version) {
            setBuilds([]);
            return;
        }
        setLoading(true);
        clearFlashes('version:modal');
        setBuilds([]);
        setSelectedBuild('');
        setDeleteFiles(false);
        setAcceptEula(false);
        getBuilds(uuid, fork, version)
            .then((data) => {
                if (Array.isArray(data.builds) && data.builds.length > 0) {
                    let sortedBuilds;
                    const isSpecialType = ['fabric', 'forge', 'neoforge', 'sponge', 'legacyfabric'].includes(
                        fork.toLowerCase()
                    );
                    if (isSpecialType) {
                        sortedBuilds = [...data.builds].sort((a, b) => {
                            const aVersion = a.name.toString();
                            const bVersion = b.name.toString();
                            return bVersion.localeCompare(aVersion, undefined, { numeric: true, sensitivity: 'base' });
                        });
                    } else {
                        sortedBuilds = [...data.builds].sort((a, b) => {
                            if (
                                typeof a.buildNumber === 'string' &&
                                typeof b.buildNumber === 'string' &&
                                /^\d+\.\d+(\.\d+)?$/.test(a.buildNumber) &&
                                /^\d+\.\d+(\.\d+)?$/.test(b.buildNumber)
                            ) {
                                return -1;
                            }
                            return parseInt(b.buildNumber.toString(), 10) - parseInt(a.buildNumber.toString(), 10);
                        });
                    }
                    setBuilds(sortedBuilds);
                    if (sortedBuilds.length > 0) {
                        if (isSpecialType) {
                            setSelectedBuild(sortedBuilds[0].name.toString());
                        } else {
                            setSelectedBuild(sortedBuilds[0].buildNumber.toString());
                        }
                    }
                } else {
                    setBuilds([]);
                }
            })
            .catch((error) => {
                addError({ key: 'version:modal', message: httpErrorToHuman(error) });
            })
            .finally(() => setLoading(false));
    }, [version, fork, uuid]);
    const submit = () => {
        clearFlashes('version:modal');
        if (!version || !selectedBuild) return;
        const selectedBuildObject = builds.find((build) => {
            if (['fabric', 'forge', 'neoforge', 'sponge', 'legacyfabric'].includes(fork.toLowerCase())) {
                return build.name.toString() === selectedBuild;
            } else {
                return build.buildNumber.toString() === selectedBuild;
            }
        });
        if (!selectedBuildObject) {
            addError({ key: 'version:modal', message: 'Selected build not found' });
            return;
        }
        return updateMinecraftVersion(uuid, {
            type: fork,
            version: version,
            build: selectedBuild,
            buildName: selectedBuildObject.name,
            deleteFiles: deleteFiles,
            acceptEula: acceptEula,
        })
            .then(() => {
                addFlash({
                    key: 'versions',
                    type: 'success',
                    message: `Minecraft version update started for ${version} (${selectedBuildObject.name}).`,
                });
                onInstalled();
            })
            .catch((error) => {
                console.error(error);
                addError({ key: 'version:modal', message: httpErrorToHuman(error) });
                throw error;
            });
    };
    return (
        <Dialog.Confirm
            open={!!version}
            onClose={onDismissed}
            title={`Install Minecraft ${version}`}
            confirm={'Install Version'}
            onConfirmed={submit}
        >
            <FlashMessageRender byKey='version:modal' className='mb-4' />
            <div className='mb-4'>
                <Label>Select Build</Label>
                <Select
                    name={'build'}
                    value={selectedBuild}
                    onChange={(e) => setSelectedBuild(e.target.value)}
                    disabled={loading || builds.length === 0}
                >
                    {loading && <option>Loading builds...</option>}
                    {!loading && builds.length === 0 && <option>No builds found</option>}
                    {builds.map((build) => {
                        const isSpecialType = ['fabric', 'forge', 'neoforge', 'sponge', 'legacyfabric'].includes(
                            fork.toLowerCase()
                        );
                        const buildValue = isSpecialType ? build.name.toString() : build.buildNumber.toString();
                        return (
                            <option key={buildValue} value={buildValue}>
                                {build.name}
                            </option>
                        );
                    })}
                </Select>
            </div>
            <div className={'bg-neutral-700 p-4 rounded border border-neutral-600 mb-4'}>
                <Switch
                    name={'deleteFiles'}
                    label={'Delete Existing Files'}
                    description={'This will delete all files in your server before installing.'}
                    defaultChecked={deleteFiles}
                    onChange={() => setDeleteFiles(!deleteFiles)}
                />
            </div>
            <div className={'bg-neutral-700 p-4 rounded border border-neutral-600'}>
                <Switch
                    name={'acceptEula'}
                    label={'Accept EULA'}
                    description={
                        'By enabling this option you confirm that you have read and accept the Minecraft EULA.'
                    }
                    defaultChecked={acceptEula}
                    onChange={() => setAcceptEula(!acceptEula)}
                />
            </div>
        </Dialog.Confirm>
    );
};
