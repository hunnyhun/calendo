import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { Habit } from '../schemas/habitSchema';
import { Task } from '../schemas/taskSchema';

// Lazy initialization to avoid calling getFirestore() before initializeApp()
function getDb() {
  return getFirestore();
}

export type Intent = 'habit' | 'task' | 'clarifying' | 'unknown';

export interface SessionState {
  conversationId: string;
  messages: Array<{
    role: string;
    content: string;
    timestamp: any;
  }>;
  missingFields?: string[];
  confidence?: number; // 0-1 indicating readiness to generate JSON
  intent?: Intent;
  extractedData?: Partial<Habit> | Partial<Task>; // Partial data collected so far
  chatMode?: string;
  lastUpdated?: any;
  title?: string;
}

/**
 * Get session state from Firestore
 */
export async function getSessionState(
  uid: string,
  conversationId: string
): Promise<SessionState | null> {
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
    const sessionState: SessionState = {
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
  } catch (error) {
    console.error('[getSessionState] Error fetching session state:', error);
    throw error;
  }
}

/**
 * Remove undefined values from an object (Firestore doesn't allow undefined)
 */
function removeUndefinedValues(obj: any): any {
  if (obj === null || obj === undefined) {
    return null;
  }
  
  if (Array.isArray(obj)) {
    return obj.map(removeUndefinedValues);
  }
  
  if (typeof obj === 'object') {
    const cleaned: any = {};
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
export async function updateSessionState(
  uid: string,
  conversationId: string,
  updates: Partial<SessionState>
): Promise<void> {
  try {
    const db = getDb();
    const conversationRef = db
      .collection('users')
      .doc(uid)
      .collection('conversations')
      .doc(conversationId);

    // Build update data and remove undefined values
    const updateData: any = {
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
  } catch (error) {
    console.error('[updateSessionState] Error updating session state:', error);
    throw error;
  }
}

/**
 * Clear session state (reset after JSON generation)
 */
export async function clearSessionState(
  uid: string,
  conversationId: string
): Promise<void> {
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
      missingFields: FieldValue.delete(),
      confidence: FieldValue.delete(),
      intent: FieldValue.delete(),
      extractedData: FieldValue.delete(),
    });

    console.log('[clearSessionState] Session state cleared:', conversationId);
  } catch (error) {
    console.error('[clearSessionState] Error clearing session state:', error);
    throw error;
  }
}

/**
 * Create a new session state
 */
export async function createSessionState(
  uid: string,
  conversationId: string,
  initialData: Partial<SessionState>
): Promise<SessionState> {
  try {
    // Build session state, only including defined values
    const sessionState: Partial<SessionState> = {
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
    } else {
      sessionState.confidence = 0; // Default value
    }
    if (initialData.intent !== undefined) {
      sessionState.intent = initialData.intent;
    } else {
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
      intent: (initialData.intent || 'unknown') as Intent,
      extractedData: initialData.extractedData,
      chatMode: initialData.chatMode,
      title: initialData.title,
      lastUpdated: new Date(),
    };
  } catch (error) {
    console.error('[createSessionState] Error creating session state:', error);
    throw error;
  }
}

