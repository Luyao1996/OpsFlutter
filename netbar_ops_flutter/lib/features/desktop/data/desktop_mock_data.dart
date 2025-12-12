import 'desktop_model.dart';

final mockLayouts = [
  DesktopLayout(
    id: '1',
    name: '默认桌面配置',
    resolution: '1920*1080',
    background: BackgroundConfig(
      url: 'https://picsum.photos/1920/1080',
      mode: 'stretch',
    ),
    icons: [
      DesktopIcon(
        id: 'icon_1',
        name: '我的电脑',
        config: DesktopIconConfig(exePath: 'explorer.exe', name: '我的电脑'),
        x: 20,
        y: 20,
      ),
      DesktopIcon(
        id: 'icon_2',
        name: '回收站',
        config: DesktopIconConfig(exePath: 'recycle.bin', name: '回收站'),
        x: 20,
        y: 120, // Grid spacing roughly 100
      ),
      DesktopIcon(
        id: 'icon_3',
        name: 'Steam',
        config: DesktopIconConfig(exePath: 'C:\\Program Files (x86)\\Steam\\steam.exe', name: 'Steam'),
        x: 120,
        y: 20,
      ),
      DesktopIcon(
        id: 'icon_4',
        name: 'WeChat',
        config: DesktopIconConfig(exePath: 'WeChat.exe', name: 'WeChat'),
        x: 120,
        y: 120,
      ),
    ],
  ),
  DesktopLayout(
    id: '2',
    name: '2K 桌面配置',
    resolution: '2560*1440',
    background: BackgroundConfig(
      url: 'https://picsum.photos/2560/1440',
      mode: 'stretch',
    ),
    icons: [
      DesktopIcon(
        id: 'icon_2k_1',
        name: '2K测试图标',
        config: DesktopIconConfig(exePath: 'test.exe', name: 'Test'),
        x: 100,
        y: 100,
      ),
    ],
  ),
];
