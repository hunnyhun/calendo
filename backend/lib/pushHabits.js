"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const app_1 = require("firebase-admin/app");
const firestore_1 = require("firebase-admin/firestore");
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
// Initialize Firebase Admin with explicit project ID
// For local execution, we need to specify the project ID
const app = (0, app_1.initializeApp)({
    projectId: 'stoa-ai-hh'
});
const db = (0, firestore_1.getFirestore)(app);
const USER_ID = '0h4sJcX21UarjCk8O1tSHbCsBl03';
// Adjust path since compiled code is in lib/, but habits are in src/habits
const HABITS_DIR = path.join(__dirname, '..', 'src', 'habits');
async function pushHabitsToFirebase() {
    try {
        console.log('🚀 Starting habit push to Firebase...');
        console.log(`📁 Reading habits from: ${HABITS_DIR}`);
        console.log(`👤 User ID: ${USER_ID}`);
        // Read all JSON files from the habits directory
        const files = fs.readdirSync(HABITS_DIR).filter(file => file.endsWith('.json'));
        console.log(`📄 Found ${files.length} habit files`);
        const habitsRef = db.collection('users').doc(USER_ID).collection('habits');
        let successCount = 0;
        let errorCount = 0;
        for (const file of files) {
            try {
                const filePath = path.join(HABITS_DIR, file);
                const fileContent = fs.readFileSync(filePath, 'utf-8');
                const habitData = JSON.parse(fileContent);
                // Add the habit to Firestore
                await habitsRef.add(habitData);
                console.log(`✅ Successfully pushed: ${file} (${habitData.name || 'Unnamed'})`);
                successCount++;
            }
            catch (error) {
                console.error(`❌ Error pushing ${file}:`, error);
                errorCount++;
            }
        }
        console.log('\n📊 Summary:');
        console.log(`   ✅ Success: ${successCount}`);
        console.log(`   ❌ Errors: ${errorCount}`);
        console.log(`   📦 Total: ${files.length}`);
        if (successCount > 0) {
            console.log('\n🎉 Habits successfully pushed to Firebase!');
        }
        process.exit(0);
    }
    catch (error) {
        console.error('❌ Fatal error:', error);
        process.exit(1);
    }
}
// Run the script
pushHabitsToFirebase();
//# sourceMappingURL=pushHabits.js.map