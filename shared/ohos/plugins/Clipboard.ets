// Copyright 2019-2026 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT
import pasteboard from '@ohos.pasteboard';
import { NativePlugin } from '../NativePlugin';

interface PlainText { text: string; label?: string; }
interface TextPayload { plainText: PlainText; }

export class Clipboard implements NativePlugin {
  async invoke(command: string, payload: string): Promise<string> {
    const board = pasteboard.getSystemPasteboard();
    switch (command) {
      case 'writeText': {
        const request = JSON.parse(payload) as TextPayload;
        await board.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, request.plainText.text));
        return 'null';
      }
      case 'readText': {
        const data = await board.getData();
        const result: TextPayload = { plainText: { text: await data.convertToText() } };
        return JSON.stringify(result);
      }
      case 'clear':
        await board.clearData();
        return 'null';
      default: throw new Error(`Unsupported clipboard command: ${command}`);
    }
  }
  close(): void {}
}
