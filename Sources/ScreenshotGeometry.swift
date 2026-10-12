import Foundation

enum ScreenshotGeometry {
    /// 选区是屏幕本地左下角坐标；图像裁剪使用左上角像素坐标。
    static func cropRect(selection: CGRect, screenSize: CGSize, imageSize: CGSize) -> CGRect? {
        guard screenSize.width > 0, screenSize.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let scale = imageSize.width / screenSize.width
        let crop = CGRect(x: selection.minX * scale,
                          y: (screenSize.height - selection.maxY) * scale,
                          width: selection.width * scale, height: selection.height * scale)
            .integral
            .intersection(CGRect(origin: .zero, size: imageSize))
        guard crop.width > 1, crop.height > 1 else { return nil }
        return crop
    }
}
