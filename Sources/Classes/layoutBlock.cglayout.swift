//
//  Layout.swift
//  CGLayout
//
//  Created by Denis Koryttsev on 29/08/2017.
//  Copyright © 2017 K-o-D-e-N. All rights reserved.
//

#if os(iOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import Cocoa
#elseif os(Linux)
import Foundation
#endif

// MARK: LayoutBlock

// TODO: Add take snapshot to specific level (or at least top level)

/// Defines frame of layout block, and child blocks
public protocol LayoutSnapshotProtocol {
    /// Frame of layout block represented as snapshot
    var snapshotFrame: CGRect { get }
    /// Snapshots of child layout blocks
    var childSnapshots: [LayoutSnapshotProtocol] { get }
}
extension CGRect: LayoutSnapshotProtocol {
    /// Returns self value
    public var snapshotFrame: CGRect { return self }
    /// Returns empty array
    public var childSnapshots: [LayoutSnapshotProtocol] { return [] }
}

// TODO: ! Add snapshot getter for specific level of hierarchy
/// Defines general methods for any layout block
public protocol LayoutBlockProtocol {
    /// Flag, defines that block will be used for layout
    var isActive: Bool { get }
    /// Snapshot for current state without recalculating
    var currentSnapshot: LayoutSnapshotProtocol { get }
    var currentRect: CGRect { get }

    /// Calculate and apply frames layout items.
    /// Should be call when parent `LayoutItem` item has corrected bounds. Else result unexpected.
    func layout()

    /// Calculate and apply frames layout items in custom space.
    ///
    /// - Parameter sourceRect: Source space
    func layout(in sourceRect: CGRect)

    /// Returns snapshot for all `LayoutItem` items in block. Attention: in during calculating snapshot frames of layout items must not changed. 
    ///
    /// - Parameter sourceRect: Source space for layout
    /// - Returns: Snapshot that contains frames layout items
    func snapshot(for sourceRect: CGRect) -> LayoutSnapshotProtocol

    /// Returns snapshot for all `LayoutItem` items in block. Does not call this method directly outside `LayoutBlockProtocol` object.
    /// Method implementation should operate `completedRects` with all `LayoutItem` items, that has been used to constrain this and child blocks.
    ///
    /// - Parameters:
    ///   - sourceRect: Source space for layout. For not top level blocks rect should define the available bounds of block
    ///   - completedRects: `LayoutItem` items with corrected frame
    /// - Returns: Snapshot that contains frames layout items
    func snapshot(for sourceRect: CGRect, completedRects: inout [(AnyObject, CGRect)]) -> LayoutSnapshotProtocol

    /// Applying frames from snapshot to `LayoutItem` items in this block. 
    /// Snapshot array should be ordered such to match `LayoutItem` items sequence.
    ///
    /// - Parameter snapshot: Snapshot represented as array of frames.
    func apply(snapshot: LayoutSnapshotProtocol)
}
public extension LayoutBlockProtocol {
    /// Returns snapshot for all `LayoutItem` items in block. 
    /// Use this method when you need to get snapshot for block, that has been constrained by `LayoutItem` items, that is not included to this block.
    /// For example: block constrained by super item and you need to get size of block.
    ///
    /// - Parameters:
    ///   - sourceRect: Source space for layout.
    ///   - constrainRects: `LayoutItem` items, that not included to block, but use for constraining.
    /// - Returns: Snapshot that contains frames layout items
    func snapshot(for sourceRect: CGRect, constrainRects: [(AnyObject, CGRect)]) -> LayoutSnapshotProtocol {
        var completedRects = constrainRects
        return snapshot(for: sourceRect, completedRects: &completedRects)
    }
}

/// Makes full layout for `LayoutItem` entity. Contains main layout, related anchor constrains and item for layout.
public final class LayoutBlock<Item: LayoutItem>: LayoutBlockProtocol {
    private var itemLayout: RectBasedLayout
    private var constraints: [LayoutConstraintProtocol]
    public private(set) weak var item: Item?

    public var isActive: Bool { return item?.superItem != nil }

    public func setLayout(_ layout: RectBasedLayout) {
        guard Thread.isMainThread else { fatalError(LayoutBlock.message(forMutating: self)) }

        self.itemLayout = layout
    }

    public func setConstraints(_ constraints: [LayoutConstraintProtocol]) {
        guard Thread.isMainThread else { fatalError(LayoutBlock.message(forMutating: self)) }

        self.constraints = constraints
    }

    public /// Snapshot for current state without recalculating
    var currentSnapshot: LayoutSnapshotProtocol {
        guard let item = item else { fatalError(LayoutBlock.message(forNotActive: self)) }
        return item.inLayoutTime.frame
    }
    public var currentRect: CGRect {
        guard let item = item else { fatalError(LayoutBlock.message(forNotActive: self)) }
        return item.inLayoutTime.frame
    }

    public init(item: Item, layout: RectBasedLayout, constraints: [LayoutConstraintProtocol] = []) {
        self.item = item
        self.itemLayout = layout
        self.constraints = constraints
    }

    public /// Calculate and apply frames layout items.
    /// Should be call when parent `LayoutItem` item has corrected bounds. Else result unexpected.
    func layout() {
        guard let item = item else { return debugWarning(LayoutBlock.message(forSkipped: self)) }

        itemLayout.apply(for: item, use: constraints.lazy.filter { $0.isActive })
    }

    public /// Calculate and apply frames layout items in custom space.
    ///
    /// - Parameter sourceRect: Source space
    func layout(in sourceRect: CGRect) {
        guard let item = item else { return debugWarning(LayoutBlock.message(forSkipped: self)) }

        itemLayout.apply(for: item, in: sourceRect, use: constraints.lazy.filter { $0.isActive })
    }

    public /// Returns snapshot for all `LayoutItem` items in block. Attention: in during calculating snapshot frames of layout items must not changed.
    ///
    /// - Parameter sourceRect: Source space for layout
    /// - Returns: Snapshot contained frames layout items
    func snapshot(for sourceRect: CGRect) -> LayoutSnapshotProtocol {
        guard let inLayout = item?.inLayoutTime, let superItem = inLayout.superItem else { fatalError(LayoutBlock.message(forNotActive: self)) }

        return itemLayout.layout(rect: inLayout.frame, from: superItem, in: sourceRect, use: constraints.lazy.filter { $0.isActive })
    }

    public /// Method for perform layout calculation in child blocks. Does not call this method directly outside `LayoutBlockProtocol` object.
    /// Layout block should be insert contained `LayoutItem` items to completedRects
    ///
    /// - Parameters:
    ///   - sourceRect: Source space for layout. For not top level blocks rect should be define available bounds of block
    ///   - completedRects: `LayoutItem` items with corrected frame
    /// - Returns: Frame of this block
    func snapshot(for sourceRect: CGRect, completedRects: inout [(AnyObject, CGRect)]) -> LayoutSnapshotProtocol {
        guard let item = item, let inLayout = self.item?.inLayoutTime, let superItem = inLayout.superItem else { fatalError(LayoutBlock.message(forNotActive: self)) }

        let source = constraints.lazy.filter { $0.isActive }.reduce(sourceRect) { (result, constraint) -> CGRect in
            let rect = constraint.isIndependent ? nil : completedRects.first { constraint.layoutItem(is: $0.0) }?.1

            debugWarning(!constraint.isIndependent && rect == nil, "Constraint operates with not actual frame of item: \(constraint)")

            let constrainRect = rect.map { constraint.convert(rectIfNeeded: $0, to: superItem) } /// converts rect to current coordinate space if needed
                ?? constraint.constrainRect(for: result, in: superItem)
            return result.constrainedBy(rect: constrainRect, use: constraint)
        }
        let frame = itemLayout.layout(rect: inLayout.frame, in: source)
        completedRects.insert((item, frame), at: 0)
        return frame
    }

    public /// Applying frames from snapshot to `LayoutItem` items in this block.
    /// Snapshot array should be ordered such to match `LayoutItem` items sequence.
    ///
    /// - Parameter snapshot: Snapshot represented as array of frames.
    func apply(snapshot: LayoutSnapshotProtocol) {
        assert(isActive, LayoutBlock.message(forNotActive: self))

        item?.frame = snapshot.snapshotFrame
    }
}

internal extension LayoutBlockProtocol {
    static func message(forSkipped block: LayoutBlockProtocol) -> String { return "Layout block was skipped, because layout item not available in: \(self)" }
    static func message(forNotActive block: LayoutBlockProtocol) -> String { return "Layout block is not active, because layout item not available in: \(self)" }
    static func message(forMutating block: LayoutBlockProtocol) -> String { return "Mutating layout block is available only on main thread \(self)" }
}

/// LayoutScheme defines layout process for some layout blocks.
/// Represented as simple set of layout blocks with the right sequence, that means
/// currently performed block has constraints related to `LayoutItem` items with corrected frame.
/// LayoutScheme can contain other layout schemes.
public struct LayoutScheme: LayoutBlockProtocol {
    private var blocks: [LayoutBlockProtocol]
    public var isActive: Bool { return blocks.contains(where: { $0.isActive }) }

    public /// Snapshot for current state without recalculating
    var currentSnapshot: LayoutSnapshotProtocol {
        var snapshotFrame: CGRect!
        return LayoutSnapshot(childSnapshots: blocks.map { block in
            let blockFrame = block.currentSnapshot.snapshotFrame
            snapshotFrame = snapshotFrame?.union(blockFrame) ?? blockFrame
            return blockFrame
        }, snapshotFrame: snapshotFrame)
    }

    public init(blocks: [LayoutBlockProtocol]) {
        self.blocks = blocks
    }

    public var currentRect: CGRect {
        guard blocks.count > 0 else { fatalError(LayoutScheme.message(forNotActive: self)) }
        return blocks.reduce(nil) { return $0?.union($1.currentRect) ?? $1.currentRect }!
    }

    public /// Calculate and apply frames layout items.
    /// Should be call when parent `LayoutItem` item has corrected bounds. Else result unexpected.
    func layout() {
        blocks.forEach { $0.layout() }
    }

    public /// Calculate and apply frames layout items.
    ///
    /// - Parameter sourceRect: Source space
    func layout(in sourceRect: CGRect) {
        blocks.forEach { $0.layout(in: sourceRect) }
    }

    public /// Applying frames from snapshot to `LayoutItem` items in this block.
    /// Snapshot array should be ordered such to match `LayoutItem` items sequence.
    ///
    /// - Parameter snapshot: Snapshot represented as array of frames.
    func apply(snapshot: LayoutSnapshotProtocol) {
        var iterator = blocks.makeIterator()
        for child in snapshot.childSnapshots {
            iterator.next()?.apply(snapshot: child)
        }
    }

    public /// Returns snapshot for all `LayoutItem` items in block. Attention: in during calculating snapshot frames of layout items must not changed.
    ///
    /// - Parameter sourceRect: Source space for layout
    /// - Returns: Snapshot contained frames layout items
    func snapshot(for sourceRect: CGRect) -> LayoutSnapshotProtocol {
        var completedFrames: [(AnyObject, CGRect)] = []
        return snapshot(for: sourceRect, completedRects: &completedFrames)
    }

    public /// Method for perform layout calculation in child blocks. Does not call this method directly outside `LayoutBlockProtocol` object.
    /// Layout block should be insert contained `LayoutItem` items to completedRects
    ///
    /// - Parameters:
    ///   - sourceRect: Source space for layout. For not top level blocks rect should be define available bounds of block
    ///   - completedRects: `LayoutItem` items with corrected frame
    /// - Returns: Frame of this block
    func snapshot(for sourceRect: CGRect, completedRects: inout [(AnyObject, CGRect)]) -> LayoutSnapshotProtocol {
        var snapshotFrame: CGRect?
        return LayoutSnapshot(childSnapshots: blocks.map { block in
            let blockSnapshot = block.snapshot(for: sourceRect, completedRects: &completedRects)
            snapshotFrame = snapshotFrame?.union(blockSnapshot.snapshotFrame) ?? blockSnapshot.snapshotFrame
            return blockSnapshot
        }, snapshotFrame: snapshotFrame ?? .zero)
    }

    public mutating func insertLayout(block: LayoutBlockProtocol, to position: Int) {
        guard Thread.isMainThread else { fatalError("Mutating layout scheme is available only on main thread") }

        blocks.insert(block, at: position)
    }

    public mutating func removeInactiveBlocks() {
        guard Thread.isMainThread else { fatalError("Mutating layout scheme is available only on main thread") }

        blocks = blocks.filter { $0.isActive }
    }
}