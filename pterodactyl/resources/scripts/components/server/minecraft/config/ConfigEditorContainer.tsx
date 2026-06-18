import React, { useEffect, useState, useRef } from 'react';
import { ServerContext } from '@/state/server';
import ServerContentBlock from '@/components/elements/ServerContentBlock';
import FlashMessageRender from '@/components/FlashMessageRender';
import useFlash from '@/plugins/useFlash';
import Spinner from '@/components/elements/Spinner';
import Label from '@/components/elements/Label';
import Input from '@/components/elements/Input';
import Switch from '@/components/elements/Switch';
import GreyRowBox from '@/components/elements/GreyRowBox';
import Select from '@/components/elements/Select';
import CodemirrorEditor from '@/components/elements/CodemirrorEditor';
import { getConfigs, saveConfig, ConfigFile } from '@/api/server/minecraft/configs';
export default () => {
    const uuid = ServerContext.useStoreState((state) => state.server.data!.uuid);
    const { clearFlashes, clearAndAddHttpError, addFlash } = useFlash();
    const [configs, setConfigs] = useState<ConfigFile[]>([]);
    const [loading, setLoading] = useState(true);
    const [selectedFile, setSelectedFile] = useState<string>('');
    const [search, setSearch] = useState('');
    const [viewMode, setViewMode] = useState<'visual' | 'raw'>('visual');
    const [visualContent, setVisualContent] = useState<any>({});
    const getRawContent = useRef<() => Promise<string>>(() => Promise.reject('no editor'));
    const handleGetRawContent = React.useCallback((callback: () => Promise<string>) => {
        getRawContent.current = callback;
    }, []);
    const [isSaving, setIsSaving] = useState(false);
    const [lastSaved, setLastSaved] = useState<Date | null>(null);
    const saveTimeoutRef = useRef<NodeJS.Timeout | null>(null);
    const isFirstLoad = useRef(true);
    const lastSavedRawContent = useRef<string | null>(null);
    useEffect(() => {
        loadConfigs();
    }, []);
    const loadConfigs = () => {
        setLoading(true);
        clearFlashes('configs');
        getConfigs(uuid)
            .then((data) => {
                setConfigs(data.configs);
                if (data.configs.length > 0 && !selectedFile) {
                    const first = data.configs.find((c) => c.content);
                    if (first) {
                        setSelectedFile(first.file);
                        setVisualContent(first.content || {});
                        isFirstLoad.current = true;
                        lastSavedRawContent.current = first.raw;
                    }
                }
            })
            .catch((error) => clearAndAddHttpError({ key: 'configs', error }))
            .finally(() => setLoading(false));
    };
    const activeConfig = configs.find((c) => c.file === selectedFile);
    useEffect(() => {
        if (selectedFile) {
            loadConfigs();
        }
    }, [viewMode]);
    useEffect(() => {
        if (activeConfig) {
            setVisualContent(activeConfig.content || {});
            isFirstLoad.current = true;
        }
    }, [selectedFile, activeConfig]);
    useEffect(() => {
        if (activeConfig) {
            lastSavedRawContent.current = activeConfig.raw;
        }
    }, [selectedFile, activeConfig]);
    useEffect(() => {
        if (viewMode !== 'visual' || !activeConfig || isFirstLoad.current) {
            if (isFirstLoad.current) isFirstLoad.current = false;
            return;
        }
        if (saveTimeoutRef.current) clearTimeout(saveTimeoutRef.current);
        setIsSaving(true);
        saveTimeoutRef.current = setTimeout(() => {
            saveConfig(uuid, activeConfig.file, visualContent, null)
                .then(() => {
                    setLastSaved(new Date());
                    setIsSaving(false);
                })
                .catch((error) => {
                    console.error('Auto-save failed:', error);
                    setIsSaving(false);
                });
        }, 1000);
        return () => {
            if (saveTimeoutRef.current) clearTimeout(saveTimeoutRef.current);
        };
    }, [visualContent, uuid, activeConfig, viewMode]);
    useEffect(() => {
        if (viewMode !== 'raw' || !activeConfig) return;
        const interval = setInterval(() => {
            getRawContent
                .current()
                .then((content) => {
                    if (content !== lastSavedRawContent.current) {
                        setIsSaving(true);
                        saveConfig(uuid, activeConfig.file, null, content)
                            .then(() => {
                                setLastSaved(new Date());
                                lastSavedRawContent.current = content;
                            })
                            .catch(console.error)
                            .finally(() => setIsSaving(false));
                    }
                })
                .catch(() => {});
        }, 1000);
        return () => clearInterval(interval);
    }, [viewMode, activeConfig, uuid]);
    const handleRawSave = () => {
        if (!activeConfig) return;
        setIsSaving(true);
        getRawContent
            .current()
            .then((content) => {
                return saveConfig(uuid, activeConfig.file, null, content).then(() => content);
            })
            .then((content) => {
                addFlash({ key: 'configs', type: 'success', message: 'Configuration saved successfully.' });
                setLastSaved(new Date());
                lastSavedRawContent.current = content;
            })
            .catch((error) => clearAndAddHttpError({ key: 'configs', error }))
            .finally(() => setIsSaving(false));
    };
    const renderVisualEditor = () => {
        if (!visualContent || Object.keys(visualContent).length === 0) {
            return (
                <div className='text-neutral-400 text-center p-8'>
                    No visual configuration available or empty file. Switch to Raw View.
                </div>
            );
        }
        const filteredKeys = Object.entries(visualContent).filter(([key]) => {
            if (key.startsWith('_') || key.includes('._') || key.match(/\.(\d+)/)) return false;
            return key.toLowerCase().includes(search.toLowerCase());
        });
        if (filteredKeys.length === 0) {
            return <div className='text-neutral-400 text-center p-8'>No matching settings found.</div>;
        }
        const SELECT_OPTIONS: Record<string, string[]> = {
            difficulty: ['peaceful', 'easy', 'normal', 'hard'],
            gamemode: ['survival', 'creative', 'adventure', 'spectator'],
        };
        return (
            <div className={'grid grid-cols-1 lg:grid-cols-2 gap-4'}>
                {filteredKeys.map(([key, value]) => (
                    <GreyRowBox key={key} className={'flex-col items-start p-4 group'}>
                        <div className={'flex items-center justify-between w-full mb-2'}>
                            <Label className={'mb-0 truncate'} title={key}>
                                {!key.includes('.')
                                    ? key.replace(/_|-/g, ' ').toUpperCase()
                                    : key.split('.').map((v, i, arr) =>
                                          i === arr.length - 1 ? (
                                              v.replace(/_|-/g, ' ').toUpperCase()
                                          ) : (
                                              <span
                                                  key={i}
                                                  className='hidden group-hover:inline text-neutral-500 text-xs mr-1'
                                              >
                                                  {v.replace(/_|-/g, ' ').toUpperCase()} /{' '}
                                              </span>
                                          )
                                      )}
                            </Label>
                        </div>
                        <div className={'w-full'}>
                            {typeof value === 'boolean' ||
                            (activeConfig?.format === 'PROPERTIES' && (value === 'true' || value === 'false')) ? (
                                <div className='flex items-center mt-2'>
                                    <Switch
                                        name={key}
                                        defaultChecked={
                                            activeConfig?.format === 'PROPERTIES'
                                                ? value === 'true'
                                                : (value as boolean)
                                        }
                                        onChange={() => {
                                            const newValue =
                                                activeConfig?.format === 'PROPERTIES'
                                                    ? value === 'true'
                                                        ? 'false'
                                                        : 'true'
                                                    : !value;
                                            setVisualContent({ ...visualContent, [key]: newValue });
                                        }}
                                    />
                                    <span className='ml-3 text-xs uppercase font-bold text-neutral-400'>
                                        {(activeConfig?.format === 'PROPERTIES' ? value === 'true' : value)
                                            ? 'Enabled'
                                            : 'Disabled'}
                                    </span>
                                </div>
                            ) : SELECT_OPTIONS[key] ? (
                                <Select
                                    value={value as string}
                                    onChange={(e) => setVisualContent({ ...visualContent, [key]: e.target.value })}
                                >
                                    {!SELECT_OPTIONS[key].includes(String(value)) && (
                                        <option value={value as string}>{String(value)}</option>
                                    )}
                                    {SELECT_OPTIONS[key].map((opt) => (
                                        <option key={opt} value={opt}>
                                            {opt.charAt(0).toUpperCase() + opt.slice(1)}
                                        </option>
                                    ))}
                                </Select>
                            ) : typeof value === 'number' ? (
                                <Input
                                    type={'number'}
                                    value={value}
                                    onChange={(e) =>
                                        setVisualContent({ ...visualContent, [key]: parseFloat(e.target.value) })
                                    }
                                />
                            ) : (
                                <Input
                                    value={value as string}
                                    onChange={(e) => setVisualContent({ ...visualContent, [key]: e.target.value })}
                                />
                            )}
                        </div>
                    </GreyRowBox>
                ))}
            </div>
        );
    };
    return (
        <ServerContentBlock title={'Minecraft Config Editor'}>
            <FlashMessageRender byKey={'configs'} className={'mb-4'} />
            <div className={'flex flex-col md:flex-row gap-4 items-start'}>
                {/* Sidebar */}
                <div className={'w-full md:w-1/4 sticky top-4'}>
                    <div className={'bg-neutral-700 rounded p-4 shadow-md'}>
                        <div className='mb-4'>
                            <Label>Config File</Label>
                            {loading ? (
                                <Spinner size='small' />
                            ) : (
                                <Select value={selectedFile} onChange={(e) => setSelectedFile(e.target.value)}>
                                    {configs
                                        .filter((config) => config.content)
                                        .map((config) => (
                                            <option key={config.file} value={config.file}>
                                                {config.file}
                                            </option>
                                        ))}
                                </Select>
                            )}
                        </div>
                        <div className='mb-4'>
                            <Label>Search Settings</Label>
                            <Input
                                type='search'
                                placeholder='Search...'
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                disabled={viewMode !== 'visual'}
                            />
                        </div>
                        <Label>View Mode</Label>
                        <div className='flex rounded bg-neutral-900 p-1'>
                            <button
                                className={`flex-1 py-1 text-xs rounded transition-colors ${
                                    viewMode === 'visual'
                                        ? 'bg-neutral-600 text-white'
                                        : 'text-neutral-400 hover:text-neutral-200'
                                }`}
                                onClick={() => setViewMode('visual')}
                                disabled={!activeConfig?.content}
                                title={
                                    !activeConfig?.content
                                        ? 'Visual editor unavailable for this file'
                                        : 'Switch to Visual Editor'
                                }
                            >
                                Visual
                            </button>
                            <button
                                className={`flex-1 py-1 text-xs rounded transition-colors ${
                                    viewMode === 'raw'
                                        ? 'bg-neutral-600 text-white'
                                        : 'text-neutral-400 hover:text-neutral-200'
                                }`}
                                onClick={() => setViewMode('raw')}
                            >
                                Raw Code
                            </button>
                        </div>
                    </div>
                </div>
                {/* Main Content */}
                <div className={'w-full md:w-3/4'}>
                    {activeConfig ? (
                        <>
                            {viewMode === 'visual' ? (
                                renderVisualEditor()
                            ) : (
                                <div
                                    className='bg-neutral-900 border border-neutral-800 rounded overflow-hidden'
                                    style={{ minHeight: '500px' }}
                                >
                                    <CodemirrorEditor
                                        mode={
                                            activeConfig.format === 'YAML'
                                                ? 'yaml'
                                                : activeConfig.format === 'TOML'
                                                ? 'toml'
                                                : 'properties'
                                        }
                                        filename={activeConfig.file}
                                        initialContent={activeConfig.raw || ''}
                                        fetchContent={handleGetRawContent}
                                        onContentSaved={handleRawSave}
                                        onModeChanged={() => {}}
                                    />
                                </div>
                            )}
                        </>
                    ) : (
                        <div
                            className={
                                'col-span-3 text-center text-neutral-400 p-8 bg-neutral-700/50 rounded border-2 border-dashed border-neutral-600'
                            }
                        >
                            Select a configuration to start editing.
                        </div>
                    )}
                </div>
            </div>
        </ServerContentBlock>
    );
};
