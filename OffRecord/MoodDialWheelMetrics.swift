import SwiftUI

struct MoodDialWheelMetrics {
    let size: CGSize
    let safeAreaInsets: EdgeInsets

    init(size: CGSize, safeAreaInsets: EdgeInsets = EdgeInsets()) {
        self.size = size
        self.safeAreaInsets = safeAreaInsets
    }

    var outerRadius: CGFloat {
        min(max(size.width * 1.06, 360), 420)
    }

    var innerRadius: CGFloat {
        min(max(outerRadius * 0.66, 240), 280)
    }

    var dialTop: CGFloat {
        size.height * 0.60
    }

    var center: CGPoint {
        CGPoint(x: size.width / 2, y: dialTop + outerRadius)
    }

    var pointerCenterY: CGFloat {
        let idealCenterY = center.y - innerRadius + 82
        let lowestCenterY = size.height - safeAreaInsets.bottom - 50
        return min(idealCenterY, lowestCenterY)
    }

    var gestureTop: CGFloat {
        max(dialTop - 56, size.height * 0.50)
    }

    var gestureHeight: CGFloat {
        max(size.height - gestureTop, 1)
    }

    var gestureCenterY: CGFloat {
        gestureTop + gestureHeight / 2
    }

    var selectedMoodScale: CGFloat {
        min(max(size.height / 852, 0.88), 1.04)
    }

    var selectedMoodCenterY: CGFloat {
        let estimatedBlockHeight = 304 * selectedMoodScale
        let headerBottom = safeAreaInsets.top + 124
        let upperCenter = dialTop - 24 - estimatedBlockHeight / 2
        let lowerCenter = headerBottom + estimatedBlockHeight / 2

        if upperCenter > lowerCenter {
            return (upperCenter + lowerCenter) / 2
        }

        return max(lowerCenter, dialTop - estimatedBlockHeight / 2)
    }
}
