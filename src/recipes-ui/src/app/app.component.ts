import { CommonModule } from "@angular/common";
import { Component, OnInit } from "@angular/core";
import { FormsModule } from "@angular/forms";
import { RouterLinkActive, RouterOutlet, RouterLink, Router } from "@angular/router";
import { AuthService, MeResponse } from "./services/auth.service";

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, CommonModule, FormsModule, RouterLinkActive, RouterLink],
  templateUrl: './app.component.html',
  styleUrl: './app.component.css'
})
export class AppComponent implements OnInit {
  title = 'client';
  currentUser: MeResponse | null = null;

  constructor(
    public auth: AuthService,
    private router: Router
  ) { }

  ngOnInit(): void {
    // Subscribe to auth state and refresh from server
    this.auth.me$.subscribe(user => {
      this.currentUser = user;
    });
    
    this.auth.refreshMe().subscribe();
  }

  onLogout(event: Event): void {
    event.preventDefault();

    this.auth.logout().subscribe({
      next: () => {
        console.log('Logout successful');
        this.router.navigate(['/login']);
      },
      error: (err) => {
        console.error('Logout failed', err);
        // Still redirect even if logout fails
        this.router.navigate(['/login']);
      }
    });
  }

  get isLoggedIn(): boolean {
    return this.auth.isLoggedIn();
  }

  get userInitials(): string {
    if (!this.currentUser?.userName) return '?';
    return this.currentUser.userName.substring(0, 2).toUpperCase();
  }

  get isAdmin(): boolean {
    return this.currentUser?.roles?.includes('Admin') ?? false;
  }
}