import axios from 'axios';
import getFileUploadUrl from '@/api/server/files/getFileUploadUrl';
import tw from 'twin.macro';
import { Button } from '@/components/elements/button/index';
import React, { useRef, useState } from 'react';
import { useFlashKey } from '@/plugins/useFlash';
import useFileManagerSwr from '@/plugins/useFileManagerSwr';
import { ServerContext } from '@/state/server';
import { WithClassname } from '@/components/types';
import { PhotographIcon } from '@heroicons/react/outline';
import Spinner from '@/components/elements/Spinner';
import { useStoreActions } from 'easy-peasy';
import { ApplicationStore } from '@/state';
export default ({ className }: WithClassname) => {
    const iconUploadInput = useRef<HTMLInputElement>(null);
    const [isLoading, setIsLoading] = useState(false);
    const { mutate } = useFileManagerSwr();
    const { addError, clearAndAddHttpError } = useFlashKey('files');
    const addFlash = useStoreActions((actions: any) => actions.flashes.addFlash);
    const uuid = ServerContext.useStoreState((state) => state.server.data!.uuid);
    const addSuccess = (message: string, title: string = 'Success') => {
        addFlash({ key: 'files', message, title, type: 'success' });
    };
    const processAndUploadIcon = async (file: File) => {
        const canvas = document.createElement('canvas');
        const ctx = canvas.getContext('2d');
        if (!ctx) {
            throw new Error('Could not get canvas context');
        }
        canvas.width = 64;
        canvas.height = 64;
        const img = new Image();
        await new Promise((resolve, reject) => {
            img.onload = resolve;
            img.onerror = reject;
            img.src = URL.createObjectURL(file);
        });
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        let width = img.width;
        let height = img.height;
        let offsetX = 0;
        let offsetY = 0;
        const scaleFactor = Math.min(64 / width, 64 / height);
        width = width * scaleFactor;
        height = height * scaleFactor;
        offsetX = (64 - width) / 2;
        offsetY = (64 - height) / 2;
        ctx.drawImage(img, offsetX, offsetY, width, height);
        const blob = await new Promise<Blob>((resolve) => {
            canvas.toBlob((b) => resolve(b!), 'image/png');
        });
        const processedFile = new File([blob], 'server-icon.png', { type: 'image/png' });
        const url = await getFileUploadUrl(uuid);
        await axios.post(
            url,
            { files: processedFile },
            {
                headers: { 'Content-Type': 'multipart/form-data' },
                params: { directory: '/' },
            }
        );
    };
    const onIconSubmission = (files: FileList) => {
        clearAndAddHttpError();
        setIsLoading(true);
        if (files.length !== 1) {
            setIsLoading(false);
            return addError('Please select only one image file.', 'Error');
        }
        const file = files[0];
        if (!file.type.startsWith('image/')) {
            setIsLoading(false);
            return addError('The selected file is not an image.', 'Error');
        }
        processAndUploadIcon(file)
            .then(() => {
                addSuccess('Server icon has been updated successfully.');
                mutate();
                setIsLoading(false);
            })
            .catch((error) => {
                setIsLoading(false);
                clearAndAddHttpError(error);
            });
    };
    return (
        <>
            <input
                type={'file'}
                ref={iconUploadInput}
                css={tw`hidden`}
                onChange={(e) => {
                    if (!e.currentTarget.files) return;
                    onIconSubmission(e.currentTarget.files);
                    if (iconUploadInput.current) {
                        iconUploadInput.current.files = null;
                    }
                }}
                accept='image/*'
            />
            <Button
                className={className}
                onClick={() => iconUploadInput.current && iconUploadInput.current.click()}
                title='Upload a server icon (64x64 PNG)'
                disabled={isLoading}
            >
                <div css={tw`flex items-center`}>
                    {isLoading ? <Spinner size='small' css={tw`mr-2`} /> : <PhotographIcon css={tw`w-4 h-4 mr-2`} />}
                    Set Icon
                </div>
            </Button>
        </>
    );
};
