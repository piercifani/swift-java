//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

package org.swift.swiftkit.core;

import org.swift.swiftkit.core.ref.SwiftCleaner;

/**
 * A Swift closure handed to Java, such as one a Swift function returns.
 *
 * <p>Generated code wraps it in a lambda of the closure's functional interface, which converts its
 * arguments and result. The Swift closure is released when this object is garbage collected.
 */
public final class SwiftClosure {
    private static final SwiftCleaner CLEANER = SwiftCleaner.create(runnable -> {
        Thread thread = new Thread(runnable, "SwiftClosureCleanerThread");
        thread.setDaemon(true);
        return thread;
    });

    private final long handle;

    /** Takes ownership of the Swift closure at {@code handle}. */
    public SwiftClosure(long handle) {
        this.handle = handle;
        CLEANER.register(this, () -> $release(handle));
    }

    /** Calls the Swift closure. Arguments and the result are boxed Java values. */
    public Object call(Object... arguments) {
        return $call(handle, arguments);
    }

    private static native Object $call(long handle, Object[] arguments);

    private static native void $release(long handle);
}
