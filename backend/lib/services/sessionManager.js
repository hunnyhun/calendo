"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getSessionState = getSessionState;
exports.updateSessionState = updateSessionState;
exports.clearSessionState = clearSessionState;
exports.createSessionState = createSessionState;
const firestore_1 = require("firebase-admin/firestore");
// Lazy initialization to avoid calling getFirestore() before initializeApp()
function getDb() {
    return (0, firestore_1.getFirestore)();
}
/**
 * Get session state from Firestore
 */
async function getSessionState(uid, conversationId) {
    try {
        const db = getDb();
        const conversationRef = db
            .collection('users')
            .doc(uid)
            .collection('conversations')
            .doc(conversationId);
        const conversationDoc = await conversationRef.get();
        if (!conversationDoc.exists) {
            return null;
        }
        const data = conversationDoc.data();
        if (!data) {
            return null;
        }
        // Map existing ConversationData to SessionState
        const sessionState = {
            conversationId,
            messages: data.messages || [],
            missingFields: data.missingFields,
            confidence: data.confidence,
            intent: data.intent,
            extractedData: data.extractedData,
            chatMode: data.chatMode,
            lastUpdated: data.lastUpdated,
            title: data.title,
        };
        return sessionState;
    }
    catch (error) {
        console.error('[getSessionState] Error fetching session state:', error);
        throw error;
    }
}
/**
 * Remove undefined values from an object (Firestore doesn't allow undefined)
 */
function removeUndefinedValues(obj) {
    if (obj === null || obj === undefined) {
        return null;
    }
    if (Array.isArray(obj)) {
        return obj.map(removeUndefinedValues);
    }
    if (typeof obj === 'object') {
        const cleaned = {};
        for (const [key, value] of Object.entries(obj)) {
            if (value !== undefined) {
                cleaned[key] = removeUndefinedValues(value);
            }
        }
        return cleaned;
    }
    return obj;
}
/**
 * Update session state in Firestore
 */
async function updateSessionState(uid, conversationId, updates) {
    try {
        const db = getDb();
        const conversationRef = db
            .collection('users')
            .doc(uid)
            .collection('conversations')
            .doc(conversationId);
        // Build update data and remove undefined values
        const updateData = {
            lastUpdated: new Date(),
        };
        // Only include fields that are actually provided (not undefined)
        if (updates.messages !== undefined) {
            updateData.messages = updates.messages;
        }
        if (updates.chatMode !== undefined) {
            updateData.chatMode = updates.chatMode;
        }
        if (updates.title !== undefined) {
            updateData.title = updates.title;
        }
        if (updates.intent !== undefined) {
            updateData.intent = updates.intent;
        }
        if (updates.confidence !== undefined) {
            updateData.confidence = updates.confidence;
        }
        if (updates.missingFields !== undefined) {
            updateData.missingFields = updates.missingFields;
        }
        if (updates.extractedData !== undefined) {
            updateData.extractedData = updates.extractedData;
        }
        // Remove any undefined values that might have slipped through
        const cleanedData = removeUndefinedValues(updateData);
        await conversationRef.set(cleanedData, { merge: true });
        console.log('[updateSessionState] Session state updated:', {
            conversationId,
            intent: updates.intent,
            confidence: updates.confidence,
            missingFieldsCount: updates.missingFields?.length || 0,
        });
    }
    catch (error) {
        console.error('[updateSessionState] Error updating session state:', error);
        throw error;
    }
}
/**
 * Clear session state (reset after JSON generation)
 */
async function clearSessionState(uid, conversationId) {
    try {
        const db = getDb();
        const conversationRef = db
            .collection('users')
            .doc(uid)
            .collection('conversations')
            .doc(conversationId);
        // Clear session-specific fields but keep conversation history
        // Use FieldValue.delete() to properly remove fields
        await conversationRef.update({
            missingFields: firestore_1.FieldValue.delete(),
            confidence: firestore_1.FieldValue.delete(),
            intent: firestore_1.FieldValue.delete(),
            extractedData: firestore_1.FieldValue.delete(),
        });
        console.log('[clearSessionState] Session state cleared:', conversationId);
    }
    catch (error) {
        console.error('[clearSessionState] Error clearing session state:', error);
        throw error;
    }
}
/**
 * Create a new session state
 */
async function createSessionState(uid, conversationId, initialData) {
    try {
        // Build session state, only including defined values
        const sessionState = {
            conversationId,
            messages: initialData.messages || [],
            lastUpdated: new Date(),
        };
        // Only add optional fields if they are defined
        if (initialData.missingFields !== undefined) {
            sessionState.missingFields = initialData.missingFields;
        }
        if (initialData.confidence !== undefined) {
            sessionState.confidence = initialData.confidence;
        }
        else {
            sessionState.confidence = 0; // Default value
        }
        if (initialData.intent !== undefined) {
            sessionState.intent = initialData.intent;
        }
        else {
            sessionState.intent = 'unknown'; // Default value
        }
        if (initialData.extractedData !== undefined) {
            sessionState.extractedData = initialData.extractedData;
        }
        if (initialData.chatMode !== undefined) {
            sessionState.chatMode = initialData.chatMode;
        }
        if (initialData.title !== undefined) {
            sessionState.title = initialData.title;
        }
        await updateSessionState(uid, conversationId, sessionState);
        // Return a properly typed SessionState
        return {
            conversationId,
            messages: initialData.messages || [],
            missingFields: initialData.missingFields,
            confidence: initialData.confidence ?? 0,
            intent: (initialData.intent || 'unknown'),
            extractedData: initialData.extractedData,
            chatMode: initialData.chatMode,
            title: initialData.title,
            lastUpdated: new Date(),
        };
    }
    catch (error) {
        console.error('[createSessionState] Error creating session state:', error);
        throw error;
    }
}
//# sourceMappingURL=sessionManager.js.map