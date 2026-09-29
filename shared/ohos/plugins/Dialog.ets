// Copyright 2019-2026 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT
import common from '@ohos.app.ability.common';
import picker from '@ohos.file.picker';
import window from '@ohos.window';
import promptAction from '@ohos.promptAction';
import { NativePlugin } from '../NativePlugin';
import { Files } from './Files';

interface MessageRequest {
  title: string; message: string; kind: string;
  okButtonLabel?: string; noButtonLabel?: string; cancelButtonLabel?: string;
}
interface MessageResponse { value: string; }
interface FileFilter { name: string; extensions: string[]; }
interface FileRequest {
  fileName?: string; filters: FileFilter[]; multiple: boolean;
  pickerMode?: string; fileAccessMode?: string;
}
interface OpenResponse { files: string[]; }
interface SaveResponse { file: string; }

export class Dialog implements NativePlugin {
  private context: common.UIAbilityContext;
  private files: Files;
  private active: boolean = true;
  constructor(context: common.UIAbilityContext, files: Files) { this.context = context; this.files = files; }

  private filters(request: FileRequest): string[] {
    return request.filters.map((filter: FileFilter): string => {
      const name = filter.name.split('|').join(' ');
      const extensions = filter.extensions.map((ext: string): string => ext === '*' ? '.*' : `.${ext}`).join(',');
      return `${name}|${extensions}`;
    });
  }

  async invoke(command: string, payload: string): Promise<string> {
    if (!this.active) throw new Error('Ability has been destroyed');
    if (command === 'showMessageDialog') {
      const request = JSON.parse(payload) as MessageRequest;
      const buttons: promptAction.Button[] = [];
      if (request.okButtonLabel) buttons.push({ text: request.okButtonLabel, color: '#007DFF' });
      if (request.noButtonLabel) buttons.push({ text: request.noButtonLabel, color: '#182431' });
      if (request.cancelButtonLabel) buttons.push({ text: request.cancelButtonLabel, color: '#182431' });
      if (buttons.length === 0) throw new Error('A native dialog must have a button');
      const win = await window.getLastWindow(this.context);
      const result = await win.getUIContext().getPromptAction().showDialog({ title: request.title, message: request.message, buttons });
      if (!this.active) throw new Error('Ability has been destroyed');
      // Return the actual selected label, preserving Tauri's custom button contract.
      const response: MessageResponse = { value: result.index >= 0 && result.index < buttons.length ? buttons[result.index].text : 'Cancel' };
      return JSON.stringify(response);
    }
    const request = JSON.parse(payload) as FileRequest;
    const view = new picker.DocumentViewPicker(this.context);
    if (command === 'showFilePicker') {
      const options: picker.DocumentSelectOptions = {
        maxSelectNumber: request.multiple ? 500 : 1,
        fileSuffixFilters: this.filters(request)
      };
      const selected = await view.select(options);
      if (!this.active) throw new Error('Ability has been destroyed');
      if (selected.length === 0) throw new Error('File selection cancelled');
      for (const uri of selected) this.files.grant(uri, true);
      const response: OpenResponse = { files: selected };
      return JSON.stringify(response);
    }
    if (command === 'saveFileDialog') {
      const options: picker.DocumentSaveOptions = {
        newFileNames: [request.fileName ?? 'Untitled'],
        fileSuffixChoices: this.filters(request)
      };
      const selected = await view.save(options);
      if (!this.active) throw new Error('Ability has been destroyed');
      if (selected.length === 0) throw new Error('File save cancelled');
      this.files.grant(selected[0], true);
      const response: SaveResponse = { file: selected[0] };
      return JSON.stringify(response);
    }
    throw new Error(`Unsupported dialog command: ${command}`);
  }
  close(): void { this.active = false; }
}
