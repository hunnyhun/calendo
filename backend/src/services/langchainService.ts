import { ChatGoogleGenerativeAI } from '@langchain/google-genai';
import { ChatPromptTemplate, MessagesPlaceholder } from '@langchain/core/prompts';
import { HumanMessage, AIMessage, SystemMessage } from '@langchain/core/messages';
import { RunnableSequence } from '@langchain/core/runnables';
import { SessionState } from './sessionManager';

export interface LangChainConfig {
  apiKey: string;
  modelName?: string;
  temperature?: number;
  useFunctionCalling?: boolean;
}

export interface ConversationResponse {
  text: string;
  intent?: 'habit' | 'task' | 'clarifying' | 'unknown';
  extractedData?: any;
  confidence?: number;
}

/**
 * Initialize LangChain with Gemini
 */
export function createLangChainModel(config: LangChainConfig): ChatGoogleGenerativeAI {
  const model = new ChatGoogleGenerativeAI({
    model: config.modelName || 'gemini-2.0-flash',
    temperature: config.temperature ?? 0.7,
    apiKey: config.apiKey,
  });

  return model;
}

/**
 * Build system prompt for habit/task creation
 */
function buildSystemPrompt(chatMode: string = 'task'): string {
  if (chatMode === 'habit') {
    return `You are Calendo AI, a helpful digital assistant specializing in habit formation and personal development. Your role is to help users create personalized habit plans through natural conversation.

HABIT CREATION APPROACH:
- Engage in a natural conversation to understand the user's habit goals
- Ask targeted clarifying questions when information is missing or unclear
- Only generate the final habit JSON when you have all necessary information and are confident
- Be supportive and encouraging throughout the conversation

WHEN TO ASK CLARIFYING QUESTIONS:
- Unclear frequency or schedule (daily, weekly, etc.)
- Missing difficulty level or user experience
- Unclear duration or repeat count
- Missing milestone information

IMPORTANT: DO NOT ask for habit name - always generate a name based on the conversation context.

WHEN TO GENERATE HABIT JSON:
- You have all required information (name should be generated automatically from context)
- User explicitly asks to create the habit
- You are confident in the habit structure
- All critical fields are specified

RESPONSE FORMAT:
- Ask questions naturally in conversation (but NOT about the name)
- When ready, indicate you're ready to create the habit
- Do not generate JSON until explicitly asked or when fully confident`;
  } else {
    return `You are Calendo AI, a helpful digital assistant specializing in task management and productivity. Your role is to help users break down goals into actionable tasks through natural conversation.

TASK CREATION APPROACH:
- Engage in a natural conversation to understand the user's task goals
- Ask targeted clarifying questions when information is missing or unclear
- Only generate the final task JSON when you have all necessary information and are confident
- Help users organize their work and break down complex goals

WHEN TO ASK CLARIFYING QUESTIONS:
- Missing task name or unclear goal
- Unclear steps or sequence
- Missing dates or deadlines
- Unclear priority or category

WHEN TO GENERATE TASK JSON:
- You have all required information
- User explicitly asks to create the task
- You are confident in the task structure
- All critical fields are specified

RESPONSE FORMAT:
- Ask questions naturally in conversation
- When ready, indicate you're ready to create the task
- Do not generate JSON until explicitly asked or when fully confident`;
  }
}

/**
 * Convert session messages to LangChain messages
 */
function convertMessagesToLangChain(messages: SessionState['messages']): Array<HumanMessage | AIMessage | SystemMessage> {
  const langChainMessages: Array<HumanMessage | AIMessage | SystemMessage> = [];

  for (const msg of messages) {
    if (msg.role === 'user') {
      langChainMessages.push(new HumanMessage(msg.content));
    } else if (msg.role === 'assistant') {
      langChainMessages.push(new AIMessage(msg.content));
    } else if (msg.role === 'system') {
      langChainMessages.push(new SystemMessage(msg.content));
    }
  }

  return langChainMessages;
}

/**
 * Create conversation chain with memory
 */
export function createConversationChain(
  model: ChatGoogleGenerativeAI,
  chatMode: string = 'task',
  sessionState?: SessionState
): RunnableSequence {
  const systemPrompt = buildSystemPrompt(chatMode);

  // Build prompt template with conversation history
  const prompt = ChatPromptTemplate.fromMessages([
    ['system', systemPrompt],
    new MessagesPlaceholder('chat_history'),
    ['human', '{input}'],
  ]);

  // Create chain
  const chain = RunnableSequence.from([
    prompt,
    model,
  ]);

  return chain;
}

/**
 * Execute conversation chain
 */
export async function executeConversation(
  model: ChatGoogleGenerativeAI,
  input: string,
  sessionState: SessionState,
  chatMode: string = 'task'
): Promise<ConversationResponse> {
  try {
    // Convert session messages to LangChain format
    const langChainMessages = convertMessagesToLangChain(sessionState.messages);

    // Add system message if not present
    const systemPrompt = buildSystemPrompt(chatMode);
    const messages = [
      new SystemMessage(systemPrompt),
      ...langChainMessages,
      new HumanMessage(input),
    ];

    // Invoke model
    const response = await model.invoke(messages);

    // Extract text response
    const text = response.content as string;

    // Basic intent detection (can be enhanced)
    let intent: ConversationResponse['intent'] = 'unknown';
    let confidence = 0.5;

    // Check for habit/task keywords
    const lowerText = text.toLowerCase();
    if (lowerText.includes('habit') || chatMode === 'habit') {
      intent = 'habit';
    } else if (lowerText.includes('task') || chatMode === 'task') {
      intent = 'task';
    }

    // Check if asking clarifying question
    if (text.includes('?') || lowerText.includes('what') || lowerText.includes('when') || lowerText.includes('how')) {
      intent = 'clarifying';
      confidence = 0.3; // Lower confidence when asking questions
    }

    return {
      text,
      intent,
      confidence,
    };
  } catch (error) {
    console.error('[executeConversation] Error executing conversation:', error);
    throw error;
  }
}

/**
 * Execute conversation with streaming support
 */
export async function* executeConversationStream(
  model: ChatGoogleGenerativeAI,
  input: string,
  sessionState: SessionState,
  chatMode: string = 'task'
): AsyncGenerator<string, void, unknown> {
  try {
    // Convert session messages to LangChain format
    const langChainMessages = convertMessagesToLangChain(sessionState.messages);

    // Add system message if not present
    const systemPrompt = buildSystemPrompt(chatMode);
    const messages = [
      new SystemMessage(systemPrompt),
      ...langChainMessages,
      new HumanMessage(input),
    ];

    // Stream response
    const stream = await model.stream(messages);

    for await (const chunk of stream) {
      if (chunk.content) {
        yield chunk.content as string;
      }
    }
  } catch (error) {
    console.error('[executeConversationStream] Error streaming conversation:', error);
    throw error;
  }
}

