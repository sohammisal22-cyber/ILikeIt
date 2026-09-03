import 'dart:async';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../core/auth/user_session_manager.dart';
import '../../core/sync/sync_manager.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/device_info_service.dart';
import '../folders/folder_screen.dart';
import '../../core/widgets/gradient_scaffold.dart';
import '../../core/widgets/glass_container.dart';
import '../../core/utils/countries.dart';

class InitialSetupScreen extends StatefulWidget {
  const InitialSetupScreen({super.key});

  @override
  State<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends State<InitialSetupScreen> {
  // Tabs state
  bool _isLogin = true;
  bool _isLoading = false;

  // Validation state
  String? _emailErrorText;
  String? _mobileErrorText;

  void _validateEmail(String value) {
    if (value.isEmpty) {
      setState(() => _emailErrorText = null);
      return;
    }
    final bool emailValid = RegExp(
      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9-]+\.[a-zA-Z]+",
    ).hasMatch(value);
    setState(() {
      _emailErrorText = emailValid ? null : 'Invalid email address';
    });
  }

  void _validateMobile(String value) {
    if (value.isEmpty) {
      setState(() => _mobileErrorText = null);
      return;
    }
    final digitsOnly = RegExp(r'^\d+$');
    if (!digitsOnly.hasMatch(value)) {
      setState(() => _mobileErrorText = 'Only digits are allowed');
      return;
    }
    if (value.length < _selectedCountry.minLength ||
        value.length > _selectedCountry.maxLength) {
      final lengthMsg = _selectedCountry.minLength == _selectedCountry.maxLength
          ? '${_selectedCountry.minLength}'
          : '${_selectedCountry.minLength}-${_selectedCountry.maxLength}';
      setState(() {
        _mobileErrorText =
            'Please enter a valid $lengthMsg-digit mobile number';
      });
      return;
    }
    setState(() => _mobileErrorText = null);
  }

  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Password Visibility
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Checkbox state (Signup only)
  bool _termsAccepted = false;

  CountryCode _selectedCountry = const CountryCode(name: 'India', code: '+91', flag: '🇮🇳', minLength: 10, maxLength: 10);

  void _selectCountry() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        String filter = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;
            final filteredCountries = countries.where((c) {
              return c.name.toLowerCase().contains(filter.toLowerCase()) ||
                  c.code.contains(filter);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.6,
              decoration: BoxDecoration(
                color: theme.colorScheme.background,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      autofocus: true,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'Search country or code...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          filter = val;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredCountries.length,
                      itemBuilder: (context, index) {
                        final country = filteredCountries[index];
                        return ListTile(
                          leading: Text(country.flag, style: const TextStyle(fontSize: 24)),
                          title: Text(country.name),
                          trailing: Text(
                            country.code,
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              _selectedCountry = country;
                              if (_mobileController.text.length > country.maxLength) {
                                _mobileController.text = _mobileController.text.substring(0, country.maxLength);
                              }
                              _validateMobile(_mobileController.text);
                            });
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;

    // Sanitize backend/network errors from being visible on UI
    String displayMessage = message;
    final lowerMsg = message.toLowerCase();
    if (lowerMsg.contains('exception') || 
        lowerMsg.contains('api key') || 
        lowerMsg.contains('socket') || 
        lowerMsg.contains('supabase')) {
      if (lowerMsg.contains('invalid login credentials')) {
        displayMessage = 'Invalid email or password. Please try again.';
      } else if (lowerMsg.contains('user already registered') || lowerMsg.contains('user_already_exists')) {
        displayMessage = 'This email address is already registered. Please log in instead.';
      } else {
        displayMessage = 'An unexpected server error occurred. Please try again later.';
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 6,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 6,
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String urlString) async {
    if (urlString.isEmpty) return;
    final url = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch URL';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open page: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GradientScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                // App Logo
                GlassContainer(
                  borderRadius: BorderRadius.circular(100),
                  height: 120,
                  width: 120,
                  padding: const EdgeInsets.all(12),
                  child: Image.asset(
                    theme.brightness == Brightness.light
                        ? 'assets/light_logo_transparent.png'
                        : 'assets/native_splash_transparent.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your one-stop solution to Save, Organize\n& Share what you like.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14.0,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Form Container
                GlassContainer(
                  padding: const EdgeInsets.all(24),
                  borderRadius: BorderRadius.circular(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Tab Selector
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color:
                              theme.cardTheme.color?.withOpacity(0.3) ??
                              Colors.black12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isLogin = true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isLogin
                                        ? colorScheme.primary
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Log In',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _isLogin
                                            ? colorScheme.onPrimary
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isLogin = false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: !_isLogin
                                        ? colorScheme.primary
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Sign Up',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: !_isLogin
                                            ? colorScheme.onPrimary
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      if (_isLogin)
                        _buildLoginForm(colorScheme, theme)
                      else
                        _buildSignupForm(colorScheme, theme),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // LOGIN FORM
  Widget _buildLoginForm(ColorScheme colorScheme, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Welcome Back',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailController,
          onChanged: _validateEmail,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            labelText: 'Email Address',
            labelStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
            errorText: _emailErrorText,
            prefixIcon: const Icon(Icons.email_outlined),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            labelText: 'Password',
            labelStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _showForgotPasswordDialog,
            child: Text(
              'Forgot Password?',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _isLoading ? null : _login,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isLoading
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: colorScheme.onPrimary,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  'Log In',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }

  // SIGNUP FORM
  Widget _buildSignupForm(ColorScheme colorScheme, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Create Account',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        // Username field
        TextField(
          controller: _usernameController,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            labelText: 'Username',
            labelStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
            prefixIcon: const Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 16),
        // Mobile Number field with country code picker
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: _selectCountry,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colorScheme.onSurfaceVariant.withOpacity(0.3),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedCountry.flag,
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _selectedCountry.code,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.arrow_drop_down,
                        color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _mobileController,
                  onChanged: _validateMobile,
                  style: theme.textTheme.bodyMedium,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(_selectedCountry.maxLength),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Mobile Number',
                    labelStyle: TextStyle(
                      color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                    ),
                    errorText: _mobileErrorText != null ? '' : null,
                    errorStyle: const TextStyle(height: 0.01, fontSize: 0),
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ),
            ],
          ),
        ),
        if (_mobileErrorText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4.0),
            child: Text(
              _mobileErrorText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        // Email field
        TextField(
          controller: _emailController,
          onChanged: _validateEmail,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            labelText: 'Email Address',
            labelStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
            errorText: _emailErrorText,
            prefixIcon: const Icon(Icons.email_outlined),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        // Password field
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            labelText: 'Password',
            labelStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Confirm Password field
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            labelText: 'Confirm Password',
            labelStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
              ),
              onPressed: () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Legal Checkbox
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 24,
              width: 24,
              child: Checkbox(
                value: _termsAccepted,
                onChanged: (val) =>
                    setState(() => _termsAccepted = val ?? false),
                activeColor: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    const TextSpan(text: 'I agree to the '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () =>
                            _launchUrl(AppConfig.instance.privacyPolicyUrl),
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Terms of Use',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () =>
                            _launchUrl(AppConfig.instance.termsUseUrl),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _isLoading ? null : _signup,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isLoading
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: colorScheme.onPrimary,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  'Sign Up',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }

  // FORGOT PASSWORD DIALOG
  void _showForgotPasswordDialog() {
    final forgotEmailController = TextEditingController(
      text: _emailController.text,
    );
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      builder: (context) {
        bool dialogLoading = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: AlertDialog(
                title: const Text('Reset Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Enter your email address to receive a password reset link.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: forgotEmailController,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: dialogLoading
                      ? null
                      : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: dialogLoading
                      ? null
                      : () async {
                          final email = forgotEmailController.text
                              .trim()
                              .toLowerCase();
                          if (email.isEmpty || !email.contains('@')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a valid email'),
                              ),
                            );
                            return;
                          }

                          setDialogState(() => dialogLoading = true);
                          try {
                            await Supabase.instance.client.auth
                                .resetPasswordForEmail(
                                  email,
                                  redirectTo: 'ilikeit://reset-password',
                                );
                            if (mounted) {
                              Navigator.pop(context);
                              _showSuccessSnackBar(
                                'Reset link sent! Please check your email inbox.',
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error sending reset link: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } finally {
                            setDialogState(() => dialogLoading = false);
                          }
                        },
                  child: dialogLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send Reset Link'),
                ),
              ],
            ),
            );
          },
        );
      },
    );
  }

  // LOGIN LOGIC
  Future<void> _login() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    final bool emailValid = RegExp(
      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9-]+\.[a-zA-Z]+",
    ).hasMatch(email);
    if (email.isEmpty || !emailValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }

    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your password')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      final session = response.session;

      if (user != null && session != null) {
        String username = '';
        String mobile = '';
        try {
          final userData = await Supabase.instance.client
              .from('users')
              .select('username, mobile_number')
              .eq('id', user.id)
              .maybeSingle();
          if (userData != null) {
            username = userData['username'] ?? '';
            mobile = userData['mobile_number'] ?? '';
          }
        } catch (e) {
          print('Error fetching user profile from database: $e');
        }

        if (username.isEmpty) {
          username = user.userMetadata?['username'] ?? '';
        }
        if (mobile.isEmpty) {
          mobile = user.userMetadata?['mobile_number'] ?? '';
        }

        await UserSessionManager.loginWithEmail(user.id, user.email!);
        await UserSessionManager.saveUserProfile(username, mobile);

        // Save device info to Supabase (fire-and-forget, non-blocking)
        DeviceInfoService.collect().then((deviceData) {
          SyncManager.instance.remoteDataSource.upsertDeviceInfo(
            user.id,
            deviceData,
          );
        }).catchError((_) {});

        // Trigger and await sync so folders are populated before navigating
        SyncManager.instance.resetUserCreated();
        try {
          await SyncManager.instance.sync();
        } catch (e) {
          print('[INITIAL_SETUP] Sync warning on login: $e');
        }

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const FolderScreen()),
          );
        }
      } else {
        throw 'Failed to sign in. Please verify your email is confirmed.';
      }
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('email not confirmed') ||
          e.code == 'email_not_confirmed') {
        _showErrorSnackBar('Account email is not verified. Please complete Sign Up first.');
      } else {
        _showErrorSnackBar(_sanitizeAuthError(e.message));
      }
    } catch (e) {
      _showErrorSnackBar('Login failed. Please check your connection and try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createPredefinedFolders() async {
    final now = DateTime.now().toIso8601String();
    final predefinedFolders = [
      {'name': 'Food', 'icon': '0xe32e', 'created_at': now}, // restaurant
      {'name': 'Travel', 'icon': '0xf195', 'created_at': now}, // travel_explore
      {'name': 'Shopping', 'icon': '0xe5dd', 'created_at': now}, // shopping_bag
      {'name': 'Sports', 'icon': '0xf04a', 'created_at': now}, // sports_basketball
      {'name': 'Knowledge', 'icon': '0xf0e6', 'created_at': now}, // school
      {'name': 'Movies', 'icon': '0xe04b', 'created_at': now}, // video_library
    ];
    for (var folder in predefinedFolders) {
      await DatabaseHelper.instance.insertFolder(folder);
    }
  }

  String _sanitizeAuthError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return 'Invalid email or password. Please try again.';
    }
    if (lower.contains('user already registered') || lower.contains('user_already_exists')) {
      return 'This email address is already registered. Please log in instead.';
    }
    if (lower.contains('unexpected_failure') ||
        lower.contains('database error') ||
        lower.contains('saving new user') ||
        lower.contains('failed to save')) {
      return 'An unexpected server error occurred. Please try again in a few moments.';
    }
    if (lower.contains('network') || lower.contains('connection') || lower.contains('host')) {
      return 'Network connection issue. Please check your internet connection.';
    }
    if (lower.contains('invalid email')) {
      return 'The email address is invalid. Please enter a valid email.';
    }
    return message;
  }

  // SIGNUP LOGIC
  Future<void> _signup() async {
    final username = _usernameController.text.trim();
    final mobileNumber = _mobileController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (username.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a username')));
      return;
    }

    if (mobileNumber.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a mobile number')));
      return;
    }

    _validateMobile(mobileNumber);
    if (_mobileErrorText != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mobileErrorText!)),
      );
      return;
    }

    final mobile = '${_selectedCountry.code}$mobileNumber';

    final bool emailValid = RegExp(
      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9-]+\.[a-zA-Z]+",
    ).hasMatch(email);
    if (email.isEmpty || !emailValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a valid email address (e.g. name@example.com)',
          ),
        ),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters')),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }

    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You must accept the Privacy Policy and Terms of Use to sign up',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Check if email already exists in the database
      final bool emailExists = await Supabase.instance.client.rpc(
        'check_email_exists',
        params: {'email_to_check': email},
      );

      if (emailExists) {
        if (mounted) {
          _showErrorSnackBar('This email address is already registered. Please log in instead.');
        }
        setState(() => _isLoading = false);
        return;
      }

      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {
          'username': username,
          'mobile_number': mobile,
        },
      );

      final user = response.user;
      final session = response.session;

      if (user != null) {
        if (session != null) {
          // Instant login if confirmations are disabled in Supabase
          await UserSessionManager.loginWithEmail(user.id, user.email!);
          await UserSessionManager.saveUserProfile(username, mobile);

          await _createPredefinedFolders();

          // Save device info to Supabase (fire-and-forget, non-blocking)
          DeviceInfoService.collect().then((deviceData) {
            SyncManager.instance.remoteDataSource.upsertDeviceInfo(
              user.id,
              deviceData,
            );
          }).catchError((_) {});

          SyncManager.instance.resetUserCreated();
          SyncManager.instance.sync();

          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const FolderScreen()),
            );
          }
        } else {
          // Confirmation is required - show OTP Verification Dialog
          if (mounted) {
            _showOtpVerificationDialog(email);
          }
        }
      }
    } on AuthException catch (e) {
      _showErrorSnackBar(_sanitizeAuthError(e.message));
    } catch (e) {
      _showErrorSnackBar('Sign up failed. Please check your connection and try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // OTP VERIFICATION DIALOG
  void _showOtpVerificationDialog(String email) {
    final otpController = TextEditingController();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isVerifying = false;
        String? dialogErrorText;
        String? dialogSuccessText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: AlertDialog(
                backgroundColor: theme.dialogBackgroundColor ?? Colors.grey[900],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Verify Email',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'We sent a verification code to $email. Please enter it below to confirm your account.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      style: theme.textTheme.bodyMedium,
                      maxLength: 8,
                      onChanged: (_) {
                        setDialogState(() {
                          if (dialogErrorText != null) dialogErrorText = null;
                          if (dialogSuccessText != null) dialogSuccessText = null;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Verification Code',
                        hintText: 'Enter code',
                        counterText: '',
                        prefixIcon: const Icon(Icons.pin_outlined),
                      ),
                    ),
                    if (dialogErrorText != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.12),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.4),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                dialogErrorText!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (dialogSuccessText != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.12),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.4),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline_rounded,
                              color: Colors.green,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                dialogSuccessText!,
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: isVerifying
                            ? null
                            : () async {
                                setDialogState(() {
                                  dialogErrorText = null;
                                  dialogSuccessText = null;
                                });
                                try {
                                  await Supabase.instance.client.auth.resend(
                                    type: OtpType.signup,
                                    email: email,
                                  );
                                  setDialogState(() {
                                    dialogSuccessText = 'A new verification code has been sent!';
                                  });
                                } on AuthException catch (e) {
                                  final message = e.message.toLowerCase();
                                  if (message.contains('security purposes') || message.contains('request this after')) {
                                    final match = RegExp(r'\d+').firstMatch(e.message);
                                    if (match != null) {
                                      final seconds = match.group(0);
                                      setDialogState(
                                        () => dialogErrorText =
                                            'Please wait $seconds seconds before requesting a new verification code.',
                                      );
                                      return;
                                    }
                                  }
                                  setDialogState(
                                    () => dialogErrorText = e.message,
                                  );
                                } catch (e) {
                                  setDialogState(
                                    () => dialogErrorText =
                                        'Failed to resend code. Please try again.',
                                  );
                                }
                              },
                        child: Text(
                          'Resend Code',
                          style: TextStyle(color: colorScheme.primary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying
                      ? null
                      : () {
                          Navigator.pop(context);
                          setState(() {
                            _isLogin = true; // Switch back to login page
                            _passwordController.clear();
                            _confirmPasswordController.clear();
                          });
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isVerifying
                      ? null
                      : () async {
                          final otp = otpController.text.trim();
                          if (otp.isEmpty) {
                            setDialogState(
                              () => dialogErrorText =
                                  'Please enter the verification code',
                            );
                            return;
                          }

                          setDialogState(() {
                            isVerifying = true;
                            dialogErrorText = null;
                          });
                          try {
                            final response = await Supabase.instance.client.auth
                                .verifyOTP(
                                  email: email,
                                  token: otp,
                                  type: OtpType.signup,
                                );

                            final user = response.user;
                            final session = response.session;

                            if (user != null && session != null) {
                              final username = user.userMetadata?['username'] ?? '';
                              final mobile = user.userMetadata?['mobile_number'] ?? '';
                              await UserSessionManager.loginWithEmail(
                                user.id,
                                user.email!,
                              );
                              await UserSessionManager.saveUserProfile(username, mobile);

                              await _createPredefinedFolders();

                              // Save device info to Supabase (fire-and-forget, non-blocking)
                              DeviceInfoService.collect().then((deviceData) {
                                SyncManager.instance.remoteDataSource.upsertDeviceInfo(
                                  user.id,
                                  deviceData,
                                );
                              }).catchError((_) {});

                              // Trigger sync since user is now logged in
                              SyncManager.instance.resetUserCreated();
                              SyncManager.instance.sync();

                              if (mounted) {
                                Navigator.pop(context); // Close dialog
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => const FolderScreen(),
                                  ),
                                );
                              }
                            } else {
                              throw 'Verification failed. Please try again.';
                            }
                          } on AuthException catch (e) {
                            String errorMessage = e.message;
                            if (errorMessage.toLowerCase().contains(
                                  'expired',
                                ) ||
                                errorMessage.toLowerCase().contains(
                                  'invalid',
                                )) {
                              errorMessage =
                                  'The verification code has expired or is invalid. Please request a new one.';
                            }
                            setDialogState(
                              () => dialogErrorText = errorMessage,
                            );
                          } catch (e) {
                            setDialogState(
                              () => dialogErrorText =
                                  'An unexpected error occurred. Please try again.',
                            );
                          } finally {
                            setDialogState(() => isVerifying = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isVerifying
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify'),
                ),
              ],
            ),
            );
          },
        );
      },
    );
  }
}

