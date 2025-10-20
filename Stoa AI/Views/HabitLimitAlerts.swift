import SwiftUI

// MARK: - Anonymous Habit Limit Alert
struct AnonymousHabitLimitSheet: View {
    @Binding var isPresented: Bool
    let onSignUp: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 60))
                    .foregroundColor(.yellow)
                
                VStack(spacing: 8) {
                    Text("Sign In Required")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Create an account to build and track habits")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 40)
            .padding(.horizontal, 20)
            
            // Benefits list
            VStack(spacing: 16) {
                Text("Benefits of Creating an Account")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.top, 30)
                
                VStack(spacing: 12) {
                    HabitBenefitRow(
                        icon: "target",
                        title: "Habit Tracking",
                        description: "Create and monitor your daily practices"
                    )
                    
                    HabitBenefitRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Progress Analytics",
                        description: "View streaks, completion rates, and insights"
                    )
                    
                    HabitBenefitRow(
                        icon: "icloud.and.arrow.up",
                        title: "Cloud Sync",
                        description: "Access your habits across all devices"
                    )
                    
                    HabitBenefitRow(
                        icon: "bell.badge",
                        title: "Smart Reminders",
                        description: "Get notified when it's time to practice"
                    )
                    
                    HabitBenefitRow(
                        icon: "laurel.leading",
                        title: "Personal Guidance",
                        description: "AI-powered habit coaching with philosophical wisdom"
                    )
                }
                .padding(.horizontal, 20)
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 12) {
                Button(action: onSignUp) {
                    HStack {
                        Image(systemName: "person.badge.plus")
                        Text("Sign Up or Log In")
                    }
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Button(action: onDismiss) {
                    Text("Maybe Later")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Free User Habit Limit Alert
struct FreeUserHabitLimitSheet: View {
    @Binding var isPresented: Bool
    let currentHabitCount: Int
    let maxFreeHabits: Int = 1
    let onUpgrade: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 20) {
                // Icon with badge
                ZStack {
                    Image(systemName: "target")
                        .font(.system(size: 50))
                        .foregroundColor(.yellow)
                    
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.red)
                        .background(Color.white, in: Circle())
                        .offset(x: 20, y: -20)
                }
                
                VStack(spacing: 8) {
                    Text("Habit Limit Reached")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("You have \(currentHabitCount) of \(maxFreeHabits) free habit")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 40)
            .padding(.horizontal, 20)
            
            // Current vs Premium comparison
            VStack(spacing: 20) {
                Text("Upgrade to Premium for More")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.top, 30)
                
                HStack(spacing: 20) {
                    // Free plan
                    VStack(spacing: 12) {
                        Text("Free")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 8) {
                            Text("\(maxFreeHabits)")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                            
                            Text("Habit")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 6) {
                            FeatureRow(text: "Basic tracking", included: true, color: .gray)
                            FeatureRow(text: "Daily check-ins", included: true, color: .gray)
                            FeatureRow(text: "Progress stats", included: false, color: .gray)
                            FeatureRow(text: "AI coaching", included: false, color: .gray)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    )
                    
                    // Premium plan
                    VStack(spacing: 12) {
                        HStack {
                            Text("Premium")
                                .font(.headline)
                                .foregroundColor(.yellow)
                            
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                        
                        VStack(spacing: 8) {
                            Text("∞")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.yellow)
                            
                            Text("Habits")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 6) {
                            FeatureRow(text: "Unlimited habits", included: true, color: .yellow)
                            FeatureRow(text: "Advanced analytics", included: true, color: .yellow)
                            FeatureRow(text: "AI habit coaching", included: true, color: .yellow)
                            FeatureRow(text: "Custom reminders", included: true, color: .yellow)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.yellow.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.yellow, lineWidth: 2)
                            )
                    )
                }
                .padding(.horizontal, 20)
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 12) {
                Button(action: onUpgrade) {
                    HStack {
                        Image(systemName: "crown.fill")
                        Text("Upgrade to Premium")
                    }
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Button(action: onDismiss) {
                    Text("Maybe Later")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Habit Benefit Row
struct HabitBenefitRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.yellow)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow.opacity(0.05))
        )
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
    let text: String
    let included: Bool
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: included ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(included ? color : .gray.opacity(0.5))
            
            Text(text)
                .font(.caption)
                .foregroundColor(included ? .primary : .secondary)
            
            Spacer()
        }
    }
}



// MARK: - Preview
#Preview("Anonymous Limit") {
    AnonymousHabitLimitSheet(
        isPresented: .constant(true),
        onSignUp: {},
        onDismiss: {}
    )
}

#Preview("Free User Limit") {
    FreeUserHabitLimitSheet(
        isPresented: .constant(true),
        currentHabitCount: 1,
        onUpgrade: {},
        onDismiss: {}
    )
}
